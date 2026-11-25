# Connection troubleshooting

## Find the intended notebook

For a local notebook, run `marimo pair list`. The CLI uses the discovered
credentials for that notebook.

For a remote server, keep the supplied URL, including any base path. If
you have a token file, use its path for both discovery and execution:

```sh
marimo pair list --url SERVER_URL --token-file TOKEN_PATH
marimo pair execute --url SERVER_URL --token-file TOKEN_PATH --notebook NOTEBOOK_ID --code 'print(1 + 1)'
```

If the token is already in `MARIMO_TOKEN`, omit `--token-file`.

An empty listing can mean the server is running but the notebook is closed.
Open the requested notebook in the browser, start its kernel, and list again.
[Startup options](finding-marimo.md)

## Check an interrupted edit

If execution ends before you receive confirmation, the edit may already
have taken effect. Inspect the same notebook before retrying. For example,
if you tried to add a cell, look for its source and check its status.
Submitting the edit again could create a duplicate.
