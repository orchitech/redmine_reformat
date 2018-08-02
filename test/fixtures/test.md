# Working

## Redmine internal link syntax is preserved

This is a [[wiki link]].

## Code highlighting is preserved

``` sql
SELECT * FROM table;
```

## Inline code can contains @

Repository is `git@github.com/user/repo`.

## Block code use backtick, not indent, if they are not preceded by a blank line

Try this:

```
echo "OK"
```

## Quotations are preserved

> I'll be back\! Ha\! You didn't know I was gonna say that, did you?

## XML tags are preserved

    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
        <array>
            <dict>
                <key>foo</key>
                <string>bar</string>
            </dict>
        </array>
    </plist>

## Plain URL should not get broken by escaped characters

http://example.com/example_site/#test

# Known limitations

## Unsupported cell formatting is dropped silently

|                         |                   |
| ----------------------- | ----------------- |
| one                     | two               |
| Cell spanning 2 columns |
| Cell spanning 2 rows    | one               |
| two                     |
| Right-aligned cell      | Left-aligned cell |

## List with code block is partially supported

The numbering will be reset after each code block, but layout is preserved:

1.  first item:

``` sql
SELECT * FROM table;
```

1.  second item:

```
rm -rf /tmp/*
```

1.  final item

But some more complex case might result in broken list layout.
