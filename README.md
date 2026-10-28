# openad5x
Free your AD5X from FlashForge. This repository is the documentation for OpenAD5X. Start at [docs/index.md](docs/index.md).

The files that go on the printer are in [AD5X-FS](https://github.com/FlashForge-C5-Modding-Group/AD5X-FS). See [docs/project-layout.md](docs/project-layout.md) for what each repository holds.

## Preview locally (optional)

The pages are plain Markdown and read fine on GitHub. For a local site with the OpenCreator theme:

```sh
python -m venv .venv
.venv/bin/python -m pip install -r docs/requirements.txt
.venv/bin/python -m mkdocs serve
```

On Windows, use `.venv\Scripts\python.exe` in place of `.venv/bin/python`.
