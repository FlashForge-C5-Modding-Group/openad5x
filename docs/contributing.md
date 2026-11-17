# Contributing documentation

Edit pages under `docs/` and add new pages to `nav` in `mkdocs.yml`. For hardware instructions,
say which printer, firmware version and source commit they're for, and how they were tested. Say
plainly when something hasn't been tested.

Use clear language, and only go into technical detail on pages where it's expected.

Before proposing a change, build the site with warnings treated as errors:

```sh
.venv/bin/python -m zensical build --strict
```

On Windows, use `.venv\Scripts\python.exe`. Install the build tool into `.venv` with
`pip install -r docs/requirements.txt`. The generated `site/` directory is not committed; only the
source Markdown and configuration are.

## Videos and other raw HTML

Markdown images and links work with relative paths. Paths inside raw HTML, such as `<video>` or
`<source src="...">`, don't: the site loads pages without a full reload, and a relative `src` is then
resolved against the page you came from. Give media in raw HTML its full URL, for example
`https://openad5x.github.io/assets/videos/<file>.mp4`.
