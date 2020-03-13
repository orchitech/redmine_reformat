# Code tests

## Inline code using @

`my code`  
E-mail works: `joe@example.com`  
`a tag:<>`  
No issue with backtick: `` echo `date` ``  
Recognizing ats when tightly surrounded: (`STARTED`/`FINISHED`)

## Multiline inline code

<code>This shall be code  
with a \*line\* break</code>

@But block structures like lists take precedence

  - list item@

@Table too

| TH@ |
| --- |
| x   |

## Backticks preffered over code tag

`should be backtick`  
`a tag:<>`  
`surrounding whitespace eaten`  
No issue with many ats: `@joe@example.com@`  
No issue with pipe: `joe|average`  
No issue with backtick: `` echo `date` ``  
This is lossy: `puts "Backticks are great, but code class is lost"`

## Where code tag still has to be used...

Tables:

| table                          |
| ------------------------------ |
| <code>no&#124;backticks</code> |
| <code>no&#124;backticks</code> |
| `backticks`                    |

New line: <code class="taskpaper">joe  
average</code>

Empty code: <code> </code>

## Collisions

  - block sequence with @at
  - sould not win over `inline code`
