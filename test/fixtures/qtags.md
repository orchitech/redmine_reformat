# Qtags - bold, italic, underlined and similar inline formatting

*Italic*  
*Also italic*  
**Bold**  
**Also bold**  
<cite>Cite is HTML only</cite>

## Special pandoc behavior

Parentheses and brackets within qtags should be interpreted as normal text: **(hello)** **\[hello\]** **{hello}**

Pandoc is fragile about dashes in strikeout text: ~~this should - be (?) striked-out~~

## Special Redmine behavior

_Underlined text_  
**[[WikiLink]]**

Redmine supports *multiline  
qtags* and even allows to  
*start with a newline*

## Prevent escaping in-word underscores

My username is joe_average or joe\_\_average or *joe or whatever.  
Friends call me joe* or whatever. My name is actually: \<first\>\_\<middle\>\_\<last\>

## Ensuring interpreting in tables

| Task                                                  | Description                                    |
| ----------------------------------------------------- | ---------------------------------------------- |
| *this would not be identified as qtags if not spaced* | spaces should be added around table delimiters |

## Collisions

  - Ok to use *within item*
  - But block \_structure
  - takes precedence\_
