# Qtags - bold, italic, underlined and similar inline formatting

## Special pandoc behavior

Parentheses within qtags should be interpreted as normal text: **(hello)**

Pandoc is fragile about dashes in strikeout text: ~~this should - be (?) striked-out~~

## Special Redmine behavior

_Underlined text_  
*Italic*  
**Bold**  
**[[WikiLink]]**

Redmine supports *multiline  
qtags* and even allows to  
*start with a newline*

## Prevent escaping in-word underscores

My username is joe_average or joe\_\_average or *joe or whatever.  
Friends call me joe* or whatever.

## Ensuring interpreting in tables

| Task                                                  | Description                                    |
| ----------------------------------------------------- | ---------------------------------------------- |
| *this would not be identified as qtags if not spaced* | spaces should be added around table delimiters |

## Collisions

  - Ok to use *within item*
  - But block \_structure
  - takes precedence\_
