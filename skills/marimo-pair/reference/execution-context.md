# Connection troubleshooting

## Find the intended notebook

For a remote server, list its notebooks using the supplied URL, including
any base path. Use the same URL and the selected notebook ID for execution:

```sh
marimo pair list --url SERVER_URL
marimo pair execute --url SERVER_URL --notebook NOTEBOOK_ID --code 'print(1 + 1)'
```

An empty listing can mean the server is running but the notebook is closed.
Open the requested notebook in the browser, start its kernel, and list again.
[Startup options](finding-marimo.md)

Local discovery handles authentication automatically. For explicit server
credentials, use the supplied token file or `MARIMO_TOKEN`.
Run `marimo pair list --help` for the supported options.

## Check an interrupted edit

If execution ends before you receive confirmation, the edit may already
have taken effect. Inspect the same notebook before retrying. For example,
if you tried to add a cell, look for its source and check its status.
Submitting the edit again could create a duplicate.
