# Standard tables

Paragraph Lorem ipsum

|    |    |    |
| -- | -- | -- |
| a1 | a2 | a3 |
| b1 | b2 |    |
| c1 |    | c2 |

| a1 | a2 | a3 |
| -- | -- | -- |
| b1 | b2 |    |
| c1 |    | c2 |

# Table with guessed header

| a1 | a2 | a3 | a4 |
| -- | -- | -- | -- |
| b1 | b2 |    |    |
| c1 |    | c2 |    |

# Table with protected pipe chars

| a1                  | a2                                    |
| ------------------- | ------------------------------------- |
| &#124;              | pipe in code: <code>&#124;</code>     |
| <code>&#124;</code> | <code>&#124;</code>                   |
| true &#124; false   | c2                                    |
| d1                  | also <code>pipe &#124; in code</code> |

# Wiki links with pipes are especially tricky

| a1        | a2                        |
| --------- | ------------------------- |
| [[Pg|As]] | [[Page#Anchor|AlsoAlias]] |

# Table delimiting

## Table after text

This is allowed by Redmine

| h1 |
| -- |
| c1 |

## Text after table - not a table

|\_. h1 |  
| c1 |  
Avoid table

## Separate table from prefix blocks unlike Redmine

| h1 |
| -- |
| c1 |
