# Code tests

## Inline code using @

`my code`  
E-mail works: `joe@example.com`  
`a tag:<>`

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
