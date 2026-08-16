# Makefile — 批量格式转换（增量构建，配合 scripts/convert.sh）
# 用法:
#   make all            # 把 vault/Attachments/_raw/* 全部转成 PDF
#   make md             # 全部转成中间态 Markdown
#   make clean          # 清空中间态与输出（保留 .cache 缓存）
#   make cache-clean    # 清空缓存（强制下次重新转换）

RAW := $(wildcard vault/Attachments/_raw/*)
STEM := $(notdir $(basename $(RAW)))
PDF := $(addprefix vault/Attachments/_out/,$(addsuffix .pdf,$(STEM)))
MD  := $(addprefix vault/Attachments/_md/,$(addsuffix .md,$(STEM)))

.PHONY: all md clean cache-clean

all: $(PDF)

md: $(MD)

vault/Attachments/_out/%.pdf: vault/Attachments/_raw/% 
	./scripts/convert.sh "$<" --to pdf -o "$@"

vault/Attachments/_md/%.md: vault/Attachments/_raw/%
	./scripts/convert.sh "$<" --to md

clean:
	rm -rf vault/Attachments/_md vault/Attachments/_out
	@echo "已清空中间态与输出（.cache 保留）"

cache-clean:
	rm -rf .cache
	@echo "已清空转换缓存"
