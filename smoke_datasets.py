"""Real-datasets smoke on native win_arm64 — the exact API slice grove-sprout uses."""
from datasets import Dataset

rows = [{"text": f"sample {i}", "label": i % 2, "drop_me": i} for i in range(100)]
ds = Dataset.from_list(rows)
print("from_list:", ds)

# batched map with remove_columns (the shim's hardest case: schema change + batching)
def tok(batch):
    return {"length": [len(t) for t in batch["text"]]}

ds2 = ds.map(tok, batched=True, batch_size=16, remove_columns=["drop_me"])
assert "length" in ds2.column_names and "drop_me" not in ds2.column_names
print("map(batched, remove_columns):", ds2)

split = ds2.train_test_split(test_size=0.2, seed=42)
assert len(split["train"]) == 80 and len(split["test"]) == 20
print("train_test_split:", split)

# parquet export/import round-trip through the datasets cache format
path = r"C:\RootClaw\docs\pyarrow_arm64_build\smoke_ds.parquet"
split["train"].to_parquet(path)
ds3 = Dataset.from_parquet(path)
assert len(ds3) == 80
print("to_parquet/from_parquet:", ds3)
print("DATASETS_SMOKE_OK")
