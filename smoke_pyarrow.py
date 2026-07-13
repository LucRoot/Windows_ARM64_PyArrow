"""pyarrow win_arm64 smoke test — run with .venv-arm64 python."""
import sys

import pyarrow as pa
import pyarrow.parquet as pq
import pyarrow.dataset as ds
import pyarrow.acero  # noqa: F401
import pyarrow.compute as pc

print("python:", sys.version.split()[0], sys.platform)
print("pyarrow:", pa.__version__)

# parquet round-trip incl. zstd codec (exercises bundled deps)
t = pa.table({"a": [1, 2, 3], "b": ["x", "y", "z"], "c": [0.5, 1.5, 2.5]})
path = "smoke.parquet"
pq.write_table(t, path, compression="zstd")
t2 = pq.read_table(path)
assert t.equals(t2), "parquet round-trip mismatch"
print("parquet zstd round-trip: OK")

# dataset + acero scan with a filter (exercises ArrowDataset/Acero DLLs)
d = ds.dataset(path, format="parquet")
out = d.scanner(filter=pc.field("a") > 1).to_table()
assert out.num_rows == 2, f"acero filter mismatch: {out.num_rows}"
print("dataset scanner + acero filter: OK")

# codec inventory actually linked into this build
import pyarrow as _pa

for codec in ("gzip", "zstd", "lz4", "snappy", "brotli", "bz2"):
    print(f"codec {codec}: {'YES' if _pa.Codec.is_available(codec) else 'no'}")
print("PYARROW_SMOKE_OK")
