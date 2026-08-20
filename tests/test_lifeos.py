"""lifeos 核心层测试（标准库 unittest，无额外依赖）

跑：python3 -m unittest discover -s tests -v
覆盖：frontmatter 序列化 / 领域模型 / 仓库读写 / 统计 / 服务 / HTML 看板 / 配置优先级。
GUI 不在这里测（见 tools/smoke_gui.py 的离屏冒烟）。
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lifeos import frontmatter as fm
from lifeos import html_dashboard, stats
from lifeos.config import Config
from lifeos.models import Item, ItemType, Priority, RunLog, Status, ThinkingNote, norm_date
from lifeos.repository import VaultRepository, safe_filename
from lifeos.services import prompts as prompt_svc
from lifeos.services import review as review_svc
from lifeos.services import runlog as runlog_svc


class TempVault(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.cfg = Config(
            vault_dir=str(self.tmp / "vault"), logs_dir=str(self.tmp / "logs"),
            prompts_dir=str(self.tmp / "prompts"), cache_dir=str(self.tmp / "cache"),
        )
        self.cfg.ensure_dirs()
        self.repo = VaultRepository(self.cfg)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


# ---------------------------------------------------------------- frontmatter
class TestFrontmatter(unittest.TestCase):
    def test_parse_and_body(self):
        text = "---\ntype: idea\ntitle: 测试\n---\n\n正文内容\n"
        data, body = fm.parse(text)
        self.assertEqual(data["type"], "idea")
        self.assertEqual(body.strip(), "正文内容")

    def test_no_frontmatter(self):
        data, body = fm.parse("# 只有正文\n")
        self.assertEqual(data, {})
        self.assertEqual(body, "# 只有正文\n")

    def test_malformed_yaml_does_not_raise(self):
        data, body = fm.parse("---\n: : : bad\n---\nbody\n")
        self.assertIsInstance(data, dict)

    def test_field_order_is_deterministic(self):
        data = {"tags": ["b"], "type": "idea", "title": "x", "status": "seed"}
        out = fm.dump_frontmatter(data)
        keys = [l.split(":")[0] for l in out.splitlines() if ":" in l and not l.startswith(" ")]
        self.assertEqual(keys, ["type", "title", "status", "tags"])

    def test_dates_are_unquoted(self):
        out = fm.dump_frontmatter({"created": "2026-08-16", "updated": "2026-08-17"})
        self.assertIn("created: 2026-08-16", out)
        self.assertNotIn('"2026-08-16"', out)

    def test_special_chars_round_trip(self):
        tricky = ["含逗号, 和冒号: 的文本", '带"引号"', "[方括号]开头", "{花括号}", "#井号",
                  "true", "123", "2026-01-01", "多行\n第二行"]
        data = {"thinking_notes": [{"t": "2026-08-16", "note": t} for t in tricky],
                "tags": tricky[:4], "next_actions": tricky}
        back, _ = fm.parse(fm.dump(data, "body"))
        self.assertEqual([n["note"] for n in back["thinking_notes"]], tricky)
        self.assertEqual([str(t) for t in back["tags"]], tricky[:4])
        self.assertEqual([str(a) for a in back["next_actions"]], tricky)

    def test_unknown_fields_preserved(self):
        out = fm.dump({"type": "idea", "自定义字段": "保留我"}, "")
        back, _ = fm.parse(out)
        self.assertEqual(back["自定义字段"], "保留我")


# ---------------------------------------------------------------- models
class TestModels(unittest.TestCase):
    def test_status_coercion_and_machine(self):
        self.assertIs(Status.coerce("DOING"), Status.DOING)
        self.assertIs(Status.coerce("不存在"), Status.SEED)
        self.assertIs(Status.SEED.next(), Status.SPROUT)
        self.assertIs(Status.ARCHIVED.next(), Status.ARCHIVED)
        self.assertEqual(Status.DOING.label, "推进中")

    def test_priority_weight_ordering(self):
        self.assertGreater(Priority.HIGH.weight, Priority.LOW.weight)
        self.assertIs(Priority.coerce(None), Priority.MEDIUM)

    def test_norm_date(self):
        self.assertEqual(norm_date("2026-8-6 12:00"), "2026-08-06")
        self.assertEqual(norm_date("不是日期"), "")

    def test_energy_and_progress_clamped(self):
        it = Item.from_text("---\ntype: idea\nstatus: seed\nenergy: 99\nprogress: -5\n---\n")
        self.assertEqual(it.energy, 10)
        self.assertEqual(it.progress, 0)

    def test_from_text_requires_type_or_status(self):
        self.assertIsNone(Item.from_text("---\ntitle: 普通笔记\n---\n正文\n"))
        self.assertIsNotNone(Item.from_text("---\ntype: idea\n---\n正文\n"))

    def test_save_is_idempotent(self):
        it = Item(title="幂等", id="x-1", created="2026-08-16", updated="2026-08-16",
                  status=Status.DOING, energy=5, progress=50, tags=["a"],
                  thinking_notes=[ThinkingNote("2026-08-16", "note")], body="# 幂等\n")
        once = it.to_text()
        self.assertEqual(once, Item.from_text(once).to_text())

    def test_updated_not_invented(self):
        """只读打开不应凭空产生 updated —— 否则每次浏览都制造 diff。"""
        it = Item.from_text("---\ntype: idea\nid: a\ntitle: t\ncreated: 2026-08-01\nstatus: seed\n---\n")
        self.assertNotIn("updated:", it.to_text())
        it.touch()
        self.assertIn("updated:", it.to_text())

    def test_last_activity_uses_notes(self):
        it = Item(created="2026-08-01", thinking_notes=[ThinkingNote("2026-08-20", "later")])
        self.assertEqual(it.last_activity, "2026-08-20")

    def test_matches_searches_notes_and_body(self):
        it = Item(title="标题", body="正文关键词", thinking_notes=[ThinkingNote("2026-08-01", "注释关键词")])
        self.assertTrue(it.matches("正文关键"))
        self.assertTrue(it.matches("注释关键"))
        self.assertFalse(it.matches("不存在"))


# ---------------------------------------------------------------- repository
class TestRepository(TempVault):
    def test_create_read_update(self):
        it = self.repo.create("我的想法", body="# 我的想法\n\n内容\n")
        self.assertTrue(it.path.exists())
        it.status = Status.DOING
        it.add_thinking_note("有进展了")
        self.repo.save(it)

        fresh = VaultRepository(self.cfg).load()
        self.assertEqual(len(fresh), 1)
        self.assertIs(fresh[0].status, Status.DOING)
        self.assertEqual(fresh[0].thinking_notes[-1].note, "有进展了")

    def test_filename_sanitised_and_deduped(self):
        self.assertEqual(safe_filename("a/b:c*d"), "a-b-c-d")
        a = self.repo.create("同名")
        b = self.repo.create("同名")
        self.assertNotEqual(a.path, b.path)

    def test_query_filters(self):
        self.repo.create("甲", status=Status.DOING)
        self.repo.create("乙", status=Status.DONE)
        self.assertEqual(len(self.repo.query(statuses={Status.DOING})), 1)
        self.assertEqual(len(self.repo.query("甲")), 1)
        self.assertEqual(len(self.repo.query(types={ItemType.IDEA})), 2)

    def test_capture_appends_and_toggles(self):
        p = self.repo.capture("第一条")
        self.repo.capture("第二条")
        self.assertEqual(p.read_text(encoding="utf-8").count("- [ ]"), 2)
        date, lines = self.repo.read_capture_log()[0]
        self.assertTrue(self.repo.toggle_capture_line(date, lines[0]))
        self.assertIn("- [x]", p.read_text(encoding="utf-8"))

    def test_capture_rejects_empty(self):
        with self.assertRaises(ValueError):
            self.repo.capture("   ")

    def test_upsert_section_replaces_not_duplicates(self):
        note = self.repo.daily_note()
        self.repo.upsert_section(note, "提醒", "- [ ] 甲")
        self.repo.upsert_section(note, "日程", "- 会议")
        self.repo.upsert_section(note, "提醒", "- [ ] 乙")
        text = note.read_text(encoding="utf-8")
        self.assertEqual(text.count("## 提醒"), 1)
        self.assertIn("- [ ] 乙", text)
        self.assertNotIn("- [ ] 甲", text)
        self.assertIn("## 日程", text)      # 别的段落不能被冲掉

    def test_archive_moves_and_sets_status(self):
        it = self.repo.create("待归档")
        p = self.repo.archive(it)
        self.assertEqual(p.parent.name, "Archive")
        self.assertIs(it.status, Status.ARCHIVED)

    def test_delete_goes_to_trash(self):
        it = self.repo.create("待删")
        old = it.path
        target = self.repo.delete(it)
        self.assertFalse(old.exists())
        self.assertTrue(target.exists())
        self.assertIn(".trash", str(target))

    def test_skips_templates_and_hidden(self):
        (self.cfg.vault / "Templates").mkdir(exist_ok=True)
        (self.cfg.vault / "Templates" / "t.md").write_text(
            "---\ntype: idea\nstatus: seed\n---\n", encoding="utf-8")
        self.repo.create("正常")
        self.assertEqual(len(self.repo.reload()), 1)

    def test_atomic_write_leaves_no_tmp(self):
        self.repo.create("原子写")
        self.assertEqual(list(self.cfg.vault.rglob("*.tmp")), [])


# ---------------------------------------------------------------- stats
class TestStats(unittest.TestCase):
    def setUp(self):
        self.items = [
            Item(title="A", created="2026-08-01", status=Status.DOING, priority=Priority.HIGH,
                 energy=8, progress=60, tags=["x"],
                 thinking_notes=[ThinkingNote("2026-08-01", "起"), ThinkingNote("2026-08-03", "转")]),
            Item(title="B", created="2026-08-02", status=Status.DONE, energy=4, progress=100, tags=["x", "y"]),
        ]

    def test_heat_counts_creation_and_notes(self):
        heat = stats.activity_heat(self.items)
        self.assertEqual(heat["2026-08-01"], 1)   # 创建当天的注释不重复计数
        self.assertEqual(heat["2026-08-03"], 1)

    def test_summary(self):
        s = stats.summarize(self.items)
        self.assertEqual((s.total, s.active, s.done), (2, 1, 1))
        self.assertEqual(s.total_notes, 2)
        self.assertEqual(s.avg_progress, 80)
        self.assertEqual(s.span_days, 3)

    def test_tag_and_status_counts(self):
        self.assertEqual(stats.tag_counts(self.items)[0], ("x", 2))
        self.assertEqual(stats.status_counts(self.items)[Status.DOING], 1)

    def test_trajectory_is_newest_first(self):
        traj = stats.trajectory(self.items)
        self.assertEqual([t[0] for t in traj], ["2026-08-03", "2026-08-01"])

    def test_empty_input_is_safe(self):
        s = stats.summarize([])
        self.assertEqual(s.total, 0)
        self.assertEqual(stats.activity_heat([]), {})
        self.assertEqual(stats.streak([]), 0)


# ---------------------------------------------------------------- services
class TestRunLogAndReview(TempVault):
    def test_append_and_load(self):
        runlog_svc.append(RunLog(objective="做了事", tools_used=["bash"], duration_seconds=2), self.cfg)
        runlog_svc.append(RunLog(objective="失败了", status="failed", errors=["boom"]), self.cfg)
        recs = runlog_svc.load(config=self.cfg)
        self.assertEqual(len(recs), 2)
        self.assertTrue(self.cfg.run_log_md.exists())
        line = json.loads(self.cfg.run_log_jsonl.read_text(encoding="utf-8").splitlines()[0])
        self.assertIn("run_id", line)

    def test_objective_required(self):
        with self.assertRaises(ValueError):
            runlog_svc.append(RunLog(objective="  "), self.cfg)

    def test_review_aggregate_and_report(self):
        runlog_svc.append(RunLog(objective="a", tools_used=["pandoc"], duration_seconds=3), self.cfg)
        runlog_svc.append(RunLog(objective="b", status="failed", errors=["缺依赖"]), self.cfg)
        st = review_svc.aggregate("2000-01-01", self.cfg)
        self.assertEqual(st.total, 2)
        self.assertEqual(st.rate, 50)
        self.assertEqual(st.errors[0], ("缺依赖", 1))
        md = review_svc.render_markdown(st)
        self.assertIn("成功率：50%", md)
        self.assertTrue(review_svc.write_report(st, config=self.cfg).exists())

    def test_load_skips_corrupt_lines(self):
        self.cfg.logs.mkdir(parents=True, exist_ok=True)
        self.cfg.run_log_jsonl.write_text('{"objective":"ok","timestamp":"2026-08-01T00:00:00Z"}\n'
                                          "不是 json\n", encoding="utf-8")
        self.assertEqual(len(runlog_svc.load(config=self.cfg)), 1)


class TestPrompts(TempVault):
    def test_scaffold_archives_raw_and_writes_doc(self):
        doc = prompt_svc.rewrite("帮我做个看板", config=self.cfg)
        self.assertEqual(doc.mode, "scaffold")
        self.assertTrue(doc.raw_path.exists() and doc.out_path.exists())
        self.assertIn("帮我做个看板", doc.content)
        self.assertIn("验收标准", doc.content)
        self.assertEqual(len(prompt_svc.list_prompts(self.cfg)), 1)

    def test_empty_rejected(self):
        with self.assertRaises(ValueError):
            prompt_svc.rewrite("  ", config=self.cfg)


# ---------------------------------------------------------------- HTML 看板
class TestHtmlDashboard(unittest.TestCase):
    def setUp(self):
        self.items = [Item(title="A", created="2026-08-01", status=Status.DOING, energy=7,
                           thinking_notes=[ThinkingNote("2026-08-02", "演进")])]

    def test_deterministic(self):
        self.assertEqual(html_dashboard.render(self.items), html_dashboard.render(self.items))

    def test_no_external_resources(self):
        out = html_dashboard.render(self.items)
        for token in ("http://", "https://", "cdn.", "<script"):
            self.assertNotIn(token, out, f"看板不应引用外部资源：{token}")

    def test_escapes_html(self):
        evil = [Item(title="<img src=x onerror=alert(1)>", created="2026-08-01", status=Status.SEED)]
        self.assertNotIn("<img src=x", html_dashboard.render(evil))

    def test_empty_vault_renders(self):
        self.assertIn("暂无记录", html_dashboard.render([]))


# ---------------------------------------------------------------- 配置
class TestConfig(unittest.TestCase):
    def test_derived_paths_follow_vault(self):
        cfg = Config(vault_dir="/tmp/v1")
        self.assertTrue(cfg.convert_md_dir.startswith("/tmp/v1"))

    def test_env_overrides_and_recomputes(self):
        old = dict(os.environ)
        try:
            # 配置目录也要隔离：不隔离的话 load() 会读到开发机上真实的
            # config.json，测试结果就跟着用户环境走了
            os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp()
            os.environ["VAULT_DIR"] = "/tmp/env-vault"
            cfg = Config.load()
            self.assertEqual(str(cfg.vault), "/tmp/env-vault")
            self.assertTrue(cfg.convert_md_dir.startswith("/tmp/env-vault"))
        finally:
            os.environ.clear()
            os.environ.update(old)

    def test_explicit_convert_dir_wins(self):
        old = dict(os.environ)
        try:
            os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp()
            os.environ["VAULT_DIR"] = "/tmp/env-vault"
            os.environ["CONVERT_MD_DIR"] = "/tmp/custom-md"
            self.assertEqual(Config.load().convert_md_dir, "/tmp/custom-md")
        finally:
            os.environ.clear()
            os.environ.update(old)


if __name__ == "__main__":
    unittest.main(verbosity=2)
