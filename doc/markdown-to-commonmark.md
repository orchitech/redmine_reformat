# Markdown to Commonmark migration in Redmine

Redmine is finally about to introduce GFM formatting to replace
the very outdated Redcarpet formatting.

`redmine_reformat` can help with conversion of the major syntax differences,
as described in `README.md`.

There is
[an interesting discussion regarding hard line breaks](https://www.redmine.org/issues/32424#note-26) -
whether to keep the default (only explicit hard breaks) or make it
configurable. Just to recap, the current Redcarpet formatter in Redmine has
hardcoded the `hard_wrap` setting, so it might become a surprise for some
users.

`redmine_reformat` is currently able to handle all the options. Just pick one
of the configurations below and run it as:
```sh
rake reformat:convert to_formatting=markdown converters_json="$convcfg"
# or if your are in hurry and not on Windows...
rake reformat:convert to_formatting=markdown converters_json="$convcfg" workers=12
```
`MarkdownToCommonmark` configurations depending on how the `common_mark`
formatter will be used in Redmine:
1.  conversion for hard line breaks **globally enabled** (default, GitLab approach):
    ```sh
    # this is currently in the default converter config in redmine_reformat
    # no need to se it explicitly
    convcfg='[{
      "from_formatting": "markdown",
      "to_formatting": "common_mark",
      "converters": [["MarkdownToCommonmark", { "hard_wrap": true }]],
      "force_crlf": false,
      "match_trailing_nl": false,
    }]'
    ```
2.  conversion for hard line breaks **globally disabled**:
    ```sh
    convcfg='[{
      "from_formatting": "markdown",
      "to_formatting": "common_mark",
      "converters": [["MarkdownToCommonmark", { "hard_wrap": false }]],
      "force_crlf": false,
      "match_trailing_nl": false,
    }]'
    ```
3.  conversion for hard line breaks **enabled on issues and comments** (GitHub approach):
    ```sh
    # based on #32424 outcome, the config default can be either changed to this
    # or it can be autodetected from settings, so that users do not have to enter
    # such configuration themselves.
    convcfg='[{
      "from_formatting": "markdown",
      "to_formatting": "common_mark",
      "items": ["Issue", "JournalDetail[Issue.description]", "Journal"]
      "converters": [["MarkdownToCommonmark", { "hard_wrap": false }]],
      "force_crlf": false,
      "match_trailing_nl": false,
    }, {
      "from_formatting": "markdown",
      "to_formatting": "common_mark",
      "converters": [["MarkdownToCommonmark", { "hard_wrap": true }]],
      "force_crlf": false,
      "match_trailing_nl": false,
    }]'
  ```
