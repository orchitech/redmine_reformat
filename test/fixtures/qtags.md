# Qtags - bold, italic, underlined and similar inline formatting

## Special pandoc behavior

Parentheses within qtags should be interpreted as normal text: **(hello)**

## Special Redmine behavior

_Underlined text_  

*Italic*  
**Bold**

## Prevent escaping tags where it can cause issues

My username is joe_average or joe__average or _joe or whatever.  
Friends call me joe_ or whatever.

## Ensuring interpreting in tables

| Task                                                  | Description                                    |
| ----------------------------------------------------- | ---------------------------------------------- |
| *this would not be identified as qtags if not spaced* | spaces should be added around table delimiters |
