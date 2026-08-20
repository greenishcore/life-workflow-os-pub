import Foundation
import Testing
@testable import LifeWorkflowKit

@Suite("Skill 模型")
struct SkillModelTests {

    @Test("能读仓库里已有的 skill 文件")
    func parsesRealSkill() throws {
        let url = repoRoot.appendingPathComponent("skills/convert-document.md")
        try #require(FileManager.default.fileExists(atPath: url.path))
        let skill = try #require(Skill.from(text: String(contentsOf: url, encoding: .utf8), url: url))
        #expect(!skill.skillID.isEmpty)
        #expect(!skill.name.isEmpty)
    }

    @Test("模板文件不会被当成 skill")
    func templateIsNotASkill() {
        let template = "---\nskill_id: {{skill_id}}\nname: {{技能名}}\nstatus: draft\n---\n\n# x\n"
        #expect(Skill.from(text: template) == nil)
        #expect(Skill.from(text: "---\nname: 没有 id\n---\n") == nil)
    }

    @Test("写回后能再读回来，字段无损")
    func roundTrip() throws {
        let skill = Skill(skillID: "convert-doc", name: "文档转换", status: .verified,
                          created: "2026-08-01", updated: "2026-08-19",
                          tags: ["flow", "pandoc"], trigger: "需要转格式时",
                          uses: 3, lastUsed: "2026-08-18",
                          sourceErrors: ["缺少 xelatex"], body: "# 文档转换\n\n步骤\n")
        let back = try #require(Skill.from(text: skill.toText()))
        #expect(back.skillID == "convert-doc")
        #expect(back.status == .verified)
        #expect(back.tags == ["flow", "pandoc"])
        #expect(back.uses == 3)
        #expect(back.lastUsed == "2026-08-18")
        #expect(back.sourceErrors == ["缺少 xelatex"])
        #expect(back.trigger == "需要转格式时")
    }

    @Test("二次保存稳定，日期不加引号")
    func stableOutput() throws {
        let skill = Skill(skillID: "a", name: "甲", created: "2026-08-01", updated: "2026-08-02")
        let once = skill.toText()
        #expect(try #require(Skill.from(text: once)).toText() == once)
        #expect(once.contains("created: 2026-08-01"))
        #expect(!once.contains("\"2026-08-01\""))
    }

    @Test("记一次使用会累加并刷新日期")
    func recordUse() {
        var skill = Skill(skillID: "a", name: "甲")
        skill.recordUse(on: "2026-08-19")
        skill.recordUse(on: "2026-08-20")
        #expect(skill.uses == 2)
        #expect(skill.lastUsed == "2026-08-20")
        #expect(!skill.updated.isEmpty)
    }

    @Test("covers 能识别错误是否已有对策")
    func coversError() {
        let skill = Skill(skillID: "a", name: "PDF 生成失败处理",
                          trigger: "生成 PDF 报错时",
                          sourceErrors: ["缺少 xelatex"],
                          body: "装 basictex 即可")
        #expect(skill.covers(error: "缺少 xelatex"))
        #expect(skill.covers(error: "basictex"))
        #expect(!skill.covers(error: "网络超时"))
        #expect(!skill.covers(error: "  "))
    }

    @Test("只有已验证的 skill 才会被判为闲置")
    func staleOnlyForVerified() {
        let old = Skill(skillID: "a", name: "甲", status: .verified,
                        created: "2026-01-01", lastUsed: "2026-01-01")
        #expect(old.isStale(today: "2026-08-20"))
        var draft = old; draft.status = .draft
        #expect(!draft.isStale(today: "2026-08-20"), "草稿本来就没在用，不该报闲置")
        var recent = old; recent.lastUsed = "2026-08-15"
        #expect(!recent.isStale(today: "2026-08-20"))
    }
}

@Suite("从日志提炼 skill")
struct SkillProposalTests {

    private func log(
        _ objective: String, status: RunLog.Status = .success,
        tools: [String] = [], errors: [String] = []
    ) -> RunLog {
        RunLog(objective: objective, toolsUsed: tools, status: status, errors: errors)
    }

    @Test("重复出现的错误会被提议沉淀为避坑 skill")
    func recurringErrorProposed() throws {
        let logs = [
            log("转 PDF", status: .failed, errors: ["缺少 xelatex"]),
            log("再转 PDF", status: .failed, errors: ["缺少 xelatex"]),
        ]
        let proposals = SkillsService.propose(logs: logs, existing: [], today: "2026-08-20")
        let pitfall = try #require(proposals.first { $0.kind == .avoidPitfall })
        #expect(pitfall.title.contains("xelatex"))
        #expect(pitfall.rationale.contains("2 次"))
        let draft = try #require(pitfall.draft)
        #expect(draft.status == .draft)
        #expect(draft.sourceErrors == ["缺少 xelatex"])
        #expect(draft.body.contains("缺少 xelatex"))
        #expect(draft.tags.contains("pitfall"))
    }

    @Test("只出现一次的错误不提议 —— 一次可能只是偶然")
    func singleErrorNotProposed() {
        let logs = [log("转 PDF", status: .failed, errors: ["偶发网络抖动"])]
        let proposals = SkillsService.propose(logs: logs, existing: [], today: "2026-08-20")
        #expect(proposals.filter { $0.kind == .avoidPitfall }.isEmpty)
    }

    @Test("已有 skill 覆盖的坑仍复发 → 报「对策未生效」而不是再建一个")
    func ineffectiveSkillFlagged() throws {
        let existing = [Skill(skillID: "pdf", name: "PDF 生成", sourceErrors: ["缺少 xelatex"])]
        let logs = [
            log("转 PDF", status: .failed, errors: ["缺少 xelatex"]),
            log("再转 PDF", status: .failed, errors: ["缺少 xelatex"]),
        ]
        let proposals = SkillsService.propose(logs: logs, existing: existing, today: "2026-08-20")
        #expect(proposals.filter { $0.kind == .avoidPitfall }.isEmpty, "不该重复建 skill")
        let ineffective = try #require(proposals.first {
            if case .ineffective = $0.kind { return true } else { return false }
        })
        #expect(ineffective.draft == nil, "提醒类没有草稿")
        #expect(!ineffective.kind.isActionable)
        #expect(ineffective.rationale.contains("没生效"))
    }

    @Test("稳定的工具组合会被提议固化为流程")
    func stableFlowProposed() throws {
        let logs = (1...3).map { log("转换文档 \($0)", tools: ["markitdown", "pandoc"]) }
        let proposals = SkillsService.propose(logs: logs, existing: [], today: "2026-08-20")
        let flow = try #require(proposals.first { $0.kind == .solidifyFlow })
        #expect(flow.title.contains("markitdown"))
        #expect(flow.title.contains("pandoc"))
        let draft = try #require(flow.draft)
        #expect(draft.tags.contains("flow"))
        #expect(draft.body.contains("转换文档"), "草稿应带上实际成功过的场景")
    }

    @Test("失败的运行不计入流程固化 —— 只固化真的成功过的")
    func failedRunsDoNotCountAsFlow() {
        let logs = (1...5).map {
            log("尝试 \($0)", status: .failed, tools: ["markitdown", "pandoc"])
        }
        let proposals = SkillsService.propose(logs: logs, existing: [], today: "2026-08-20")
        #expect(proposals.filter { $0.kind == .solidifyFlow }.isEmpty)
    }

    @Test("单个工具不算组合")
    func singleToolIsNotAFlow() {
        let logs = (1...5).map { log("跑 \($0)", tools: ["pandoc"]) }
        let proposals = SkillsService.propose(logs: logs, existing: [], today: "2026-08-20")
        #expect(proposals.filter { $0.kind == .solidifyFlow }.isEmpty)
    }

    @Test("工具组合与顺序无关")
    func flowOrderIndependent() {
        let logs = [
            log("a", tools: ["pandoc", "markitdown"]),
            log("b", tools: ["markitdown", "pandoc"]),
            log("c", tools: ["pandoc", "markitdown"]),
        ]
        let proposals = SkillsService.propose(logs: logs, existing: [], today: "2026-08-20")
        #expect(proposals.filter { $0.kind == .solidifyFlow }.count == 1, "顺序不同不该算两组")
    }

    @Test("长期没用过的已验证 skill 会被提醒")
    func staleSkillFlagged() throws {
        let existing = [Skill(skillID: "old", name: "老技能", status: .verified,
                              created: "2026-01-01", lastUsed: "2026-01-05")]
        let proposals = SkillsService.propose(logs: [], existing: existing, today: "2026-08-20")
        let stale = try #require(proposals.first {
            if case .stale = $0.kind { return true } else { return false }
        })
        #expect(stale.title == "老技能")
        #expect(stale.draft == nil)
    }

    @Test("没有日志也没有 skill 时，不产生噪音提议")
    func emptyInputNoProposals() {
        #expect(SkillsService.propose(logs: [], existing: [], today: "2026-08-20").isEmpty)
    }

    @Test("生成的 skill id 是文件名安全的")
    func slugIsFilenameSafe() {
        let slug = SkillsService.slug(from: "转换失败：/path/to/file.pdf 无法读取！")
        #expect(!slug.contains("/"))
        #expect(!slug.contains("："))
        #expect(!slug.hasPrefix("-"))
        #expect(!slug.hasSuffix("-"))
        #expect(!slug.isEmpty)
        #expect(SkillsService.slug(from: "！！！").isEmpty == false, "全是符号也要有兜底 id")
    }

    @Test("草稿可以直接落盘并读回")
    func draftIsPersistable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-skills-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let logs = [
            log("转 PDF", status: .failed, errors: ["缺少 xelatex"]),
            log("再转 PDF", status: .failed, errors: ["缺少 xelatex"]),
        ]
        let proposal = try #require(SkillsService.propose(logs: logs, existing: [],
                                                          today: "2026-08-20").first)
        let draft = try #require(proposal.draft)
        let url = try SkillsService.save(draft, to: dir)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let loaded = SkillsService.load(from: dir)
        #expect(loaded.count == 1)
        #expect(loaded[0].skillID == draft.skillID)
        #expect(loaded[0].sourceErrors == ["缺少 xelatex"])
    }

    @Test("加载时跳过下划线开头的模板文件")
    func loadSkipsTemplates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-skills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "---\nskill_id: {{x}}\nname: 模板\n---\n".write(
            to: dir.appendingPathComponent("_template.md"), atomically: true, encoding: .utf8)
        try SkillsService.save(Skill(skillID: "real", name: "真技能"), to: dir)
        #expect(SkillsService.load(from: dir).map(\.skillID) == ["real"])
    }
}
