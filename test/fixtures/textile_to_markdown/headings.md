# Normal heading

## Redmine allows for indenting a headline

  - list item
  - item2

# This would be also continuation but probably wasn't meant to be.

Lorem ipsum.

# Make sure textile prefix blocks are not misdetected

## Allow lists directly after prefix textile block

  - Users suffer with this in Redmine
  - Help them though the converted edit history might be tricky

## Allow code directly after prefix textile block

```
Let's allow this contrary to Redmine.
```

```
But prefix blocks directly after should be supressed
```

  
h2. This is not a heading

  - A list
  - also supresses matching a textile prefix block directly after it  
    h2. This is not a heading
