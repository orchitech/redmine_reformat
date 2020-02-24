# Redmine Reformat - A Swiss-Army Knife for Converting Redmine Rich Text Data

[![Build Status](https://travis-ci.com/orchitech/redmine_reformat.svg?branch=master)](https://travis-ci.com/orchitech/redmine_reformat)

Redmine Reformat is a [Redmine](http://www.redmine.org/) plugin providing
a rake task for flexible rich-text field format conversion.

## Prepare and Install

### Database Backup

Either backup your database or clone your Redmine instance completely.
A cloned Redmine instance allows you to compare conversion results with
the original.

### Install

```sh
cd $REDMINE_ROOT
git -C plugins clone https://github.com/orchitech/redmine_reformat.git
bundle install
```
And restart your Redmine.

### Installing Converter Dependencies

If using `TextileToMarkdown` converter, [install pandoc](https://pandoc.org/installing.html).
The other provided converters have no direct dependencies.

## Basic Usage

Current format Textile - convert all rich text to Markdown using the default
`TextileToMarkdown` converter setup:
```sh
rake reformat to_formatting=markdown
```

Dry run:
```sh
rake reformat to_formatting=markdown dryrun=1
```

Parallel processing (Unix/Linux only):
```sh
rake reformat to_formatting=markdown workers=10
```

If already using the `commmon_mark` format patch
(see [#32424](https://www.redmine.org/issues/32424)):
```sh
convcfg='[{
  "from_formatting": "textile",
  "to_formatting": "common_mark",
  "converters": "TextileToMarkdown"
}]'
rake reformat to_formatting=common_mark converters_json="$convcfg"
```

Convert to HTML (assuming a hypothetical `html` rich text format):
```sh
convcfg='[{
  "from_formatting": "textile",
  "to_formatting": "html",
  "converters": "RedmineFormatter"
}]'
rake reformat to_formatting=html converters_json="$convcfg"
```

Convert using an external web service through intermediate HTML:
```sh
convcfg='[{
  "from_formatting": "textile",
  "to_formatting": "common_mark",
  "converters": [
    ["RedmineFormatter"],
    ["Ws", "http://localhost:4000/turndown-uservice"]
  ]
}]'
rake reformat to_formatting=common_mark converters_json="$convcfg"
```

Other advanced scenarios are covered below.

## Features

- Conversion can be run on a per-project, per-object and per-field basis.
- Different sets of data can use different conversions - useful if some parts
  of your Redmine use different syntax flavours.
- Supports custom fields, journals and even custom field journals.
- Supports parallel conversion in several processes - especially handy when external
  tools are used (pandoc, web services).
- Transaction safety even for parallel conversion.
- Currently supported converters:
  - `TextileToMarkdown` - a Pandoc-based Textile to Markdown converter. Works on markup
    level. Battle-tested on quarter a million strings. See below for details.
  - `RedmineFormatter` - produces HTML using Redmine's internal formatter. Useful
    when chaining with external converters. See below for details.
  - `Ws` - calls an external web service, providing input in the POST body and
    expecting converted output in the response body.
  - Feel free to submit more :)
- Conversions can be chained - e.g. convert Atlassian Wiki Markup (roughly similar
  to Textile) to HTML and then HTML to Markdown using Turndown.

## Conversion Success Rate and Integrity

`TextileToMarkdown` converter:
- Uses heavy preprocessing using adapted Redmine code, which provides solid
  compatibility compared to plain pandoc usage.
- Tested on a Redmine instance with \~250k strings ranging from tiny comments to large
  wiki pages.
- The objects in source (Textile) and converted (Markdown) instances were
  rendered through HTML GUI, the HTMLs were normalized and diffed with exact
  match ratio of 86% with the default `Redcarpet` Markdown renderer.
- A significant part of the differing outputs are actually fixes of improper
  user syntax. :)
- As `Redcarpet` is obsolete and cannot encode all the rich text constructs,
  better results are expected with the new `CommonMarker` Markdown/GFM
  implementation.
- The majority of differences are because of "garbage-in garbage-out" markup.
- Part of the differences are caused by correcting some typical user mistakes in
  Textile markup, mostly missing empty line after headings.
- The results are indeed subject to rich-text format culture within your teams.
- Please note that 100% match is not even desired, see below for more details.
  We believe that the accuracy is approaching 100% of what's possible to match.

Conversion integrity:
- Guaranteed using database transaction(s) covering whole conversion.
- There are a few places where Redmine does not use `ORDER BY`. The order then
  depends on DB implementation and usually reflects record insertion or
  modification order. The conversion is done in order of IDs, which helps to
  keep the unordered order stable. Indeed, not guaranteed at all.

Parallel processing:
- Data are split in non-overlapping sets and then divided among worker
  processes.
- Each worker is converting its own data subset in its own transaction. After
  successful completion, the worker waits on all other workers to complete
  successfuly before commiting the transaction.
- The ID-ordered conversion is also ensured in parallel processing - each
  transaction has its ID range and transactions are commited on order of
  their ID ranges.

## Advanced Scenarios

Use different converter configurations for certain projects and items:
```json
[{
    "projects": ["syncedfromjira"],
    "items": ["Issue", "JournalDetail[Issue.description]", "Journal"],
    "converters": [
      ["Ws", "http://markup2html.uservice.local:4001"],
      ["Ws", "http://turndown.uservice.local:4000"]
    ]
  }, {
    "from_formatting": "textile",
    "converters": "TextileToMarkdown"
  }
]
```

To convert only a part of the data, use `null` in place of the converter chain:
```json
[{
  "projects": ["myproject"],
  "to_formatting": "common_mark",
  "converters": "TextileToMd"
}, {
  "from_formatting": "textile",
  "to_formatting": "common_mark",
  "converters": null
}]
```

## Provided Converters

For more information on markup converters, see
[Markup Conversion Analysis and Design](doc/markup-conversion.md).

### Configuring Converters

Converters are specified as an array of converter instances.
Each converter instance is specified as an array of converter class
name and contructor arguments.
If there is just one converter, the outer array can be omitted,
e.g. `[["TextileToMd"]]` can be specified as `["TextileToMd"]`.
If such converter has no arguments, it can be specified as a string,
e.g. `"TextileToMd"`.

Please note that removing the argument-encapsulating array leads to
misinterpreting the configuration if there are more converters. E.g.
~~`["RedmineFormatter", ["Ws", "http://localhost:4000"]]`~~ would be
interpreted as a single converter with an array argument. A full
specification is required in such cases, e.g.
`[["RedmineFormatter"], ["Ws", "http://localhost:4000"]]`.

### `TextileToMd`

Usage: `'TextileToMd'`\
Arguments: (none)

`TextileToMd` uses Pandoc for the actual conversion. Before pandoc is called,
the input text is subject to extensive preprocessing, often derived from Redmine
code. Placeholderized parts are later expanded after pandoc conversion.

`TextileToMd` is used in default converter config for source markup
`textile` and target `markdown`.

Although there is some partial parsing, the processing is rather performed
on source level and even some user intentions are recognized:
- First line in tables is treated as a header if all cells are strong / bold.
- Headings are terminated even if there is no blank line after them. This is
  usually a user mistake, often leading to making whole block a heading,
  which is not possible in Markdown.
- Space-indented constructs are less often treated as continuations compared
  to the current Textile parser in Redmine. Again, it is usually a user
  mistake and this was changing over time in Redmine. For example, lists
  were allowed to be space-indented until Redmine 3.4.7.
- Footnote refernces bypass pandoc and reconstructed using the placeholder
  mechanism.
- Unbalanced code blocks are tried to be detected and handled correctly.

Generated Markdown is intended to be as compatible as possible since, so
that it works even with the Redcarpet Markdown renderer. E.g. Markdown tables
are formatted in ASCII Art-ish format, as there were cases wher compacted
tables were not recognized correctly by Redcarpet.

See the test fixtures for more details. We admin the conversion is opinionated
and feel free to submit PRs to make it configurable.

<ins>Further development remarks</ins>: conversion utilizing pandoc became
an enormous beast. The amount of code in the preprocessor is comparable
to the Redmine/Redcloth3 renderer. It would have been better if pandoc
hadn't been involved at all - in terms of code complexity, speed and
external dependencies.

### `RedmineFormatter`

Usage: `'RedmineFormatter'`\
Arguments: (none)

`RedmineFormatter` uses monkey-patched internal Redmine renderer -
`textilizable()`. It converts any format supported by Redmine to
HTML in the same ways as Redmine does it. The monkey patch blocks
macro expansion and keeps wiki links untouched.

### `Ws`

Usage: `['Ws', '<url>']`\
Arguments:
- `url` - address of the web service that performs conversion.

`Ws` performs HTTP POST request to the given URL and passess
text to convert in the request body. The result is expected in the
response body. This allows fast and easy integration with converters
in different programming languages on various platforms.

### `Log`

Usage: `['Log', options]`\
Arguments:
- `options` - a hash with optional arguments:
  - `text_re`: regexp string for text to be matched
  - `reference_re`: regexp string for references to be matched
  - `print`: what from the matched text should be printed:
    -  `none` - reference only, no text
    -  `first` - also print first match of the text
    -  `all` - also print all matches of the text

`Log` logs what is going through the converter chain. Useful for
debugging or searching for specific syntax within rich text data.
The converter hands over the input as is.

## History

1. `convert_textile_to_markdown` script was built upon @sigmike
   [answer on Stack Overflow](http://stackoverflow.com/a/19876009)
2. later [slightly modified by Hugues C.](http://www.redmine.org/issues/22005)
3. Completed by Ecodev and
   [published on GitHub](https://github.com/Ecodev/redmine_convert_textile_to_markown).
4. Significantly improved by Planio / Jens Krämer:
   [GitHub fork](https://github.com/planio-gmbh/redmine_convert_textile_to_markown)
5. Conversion rewritten by Orchitech and created the conversion framework
   `redmine_reformat`. Released under GPLv3.
