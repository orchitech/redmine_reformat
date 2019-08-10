# Markdown Table Formatter

A Ruby class to normalize column lengths in a markdown table

* Reads in a Markdown table
* Properly pads each cell to aligns all column separators
* Returns the formatted table as markdown

## Usage

```ruby
input = File.open('input.md').read
table = MarkdownTableFormatter.new input
File.write 'output.md', table.to_md
```

## Project status

It worked for my use case. Right now they're aren't any tests.

## License

MIT
