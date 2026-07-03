# Research Corpus

这个目录专门保存自动浏览和搜索过的对标资料。

默认批量采集命令：

```bash
python run_benchmark.py collect --target-creators 100 --notes-per-creator 10
```

采集结果会保存为：

```text
data/research/corpus/YYYY-MM-DD-HHMMSS-xhs-benchmark-corpus.json
```

这个目录已被 `.gitignore` 忽略，只作为本地研究资料库，不提交到 GitHub。
