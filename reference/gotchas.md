# Gotchas

## Cached module availability

Some libraries cache optional-dependency availability at import time. Installing
a package mid-session via `ctx.install_packages()` won't update those caches.
The user may need to restart the kernel — but try known workarounds first.

### Polars + pyarrow

`df.to_pandas()` fails with `ModuleNotFoundError: pa.Table requires 'pyarrow'`.

**Workaround** — run in a cell (the side-effect must persist across executions):

```python
import pyarrow as _pa
import polars.dataframe.frame as _frame_mod
_frame_mod.pa = _pa
```
