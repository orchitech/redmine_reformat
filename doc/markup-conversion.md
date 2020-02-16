# Markup Conversion Analysis and Design

## Markup Conversion Particularities

Conversion of user-written markup turned out to be an interesting topic.
We've identified a few particularities making the task distinct:
- Users do not really follow markup syntax. The texts commonly contain
  copy&pasted sections without any protection, effectively creating a "zoo"
  of random markup tags not intended to have special meaning.
- Markup specifications tend to be informal and vague. Even though Commonmark
  and GFM in particular went in the right direction with their extensive specs,
  the exact behavior is always determined by each particular implementation
  and its version.
- Markup specs only deal with well-formed sources. Very few clues are
  provided on interpreting the opposite.
- The conversion is made on versioned content. Individual versions differ
  both in syntax and semantic contents. Users expect the diffs to be
  somewhat similar before and after conversion. This may become even more
  tricky if the contents represents some form of a contract, modifications
  are binding etc.

## Markup Conversion Approaches

Based on the syntax consideration, we can categorize conversion approaches as
1. Source-level transformations - the source markup format is parsed rather on
   the lexical level and the conversion is done by substituting one set of known
   constructs into another set of contructs.
2. Render-level transformations - the source markup format is parsed and
   rendered to HTML using its normal rendering mechanism. Then some sort of
   inverse rendering is applied to produce the new markup format.

## Picking an Appropriate Approach

The render-level transformation is appropriate if:
- the rendered HTML output is semantic enough to reconstruct semantic features
  in the target format
- it is applied on well-formed documents,
- eventual mistakes in the source markup format have local and limited impact
- there is benefit of HTML as a common intermediate format

The source-level transformations are more appropriate if:
- the markup sources are tread as authoritative information
- the conditions for render-level transformations are not met
- the source markup can render into HTML that can't be easily
  inverse-rendered to the target markup
- we want to smartly and consistently treat typical markup issues
  in our data

Consider the following example. Users were typing lists with a leading
space (revision r1), which started to be behave differently since Redmine
3.4.7. A user removed the leading spaces in revision r2.
The table shows different behavior of:
- Source→MD represented by the `TextileToMarkdown`converter and
- Render→MD represented by an external (`Ws`) converter derived from
  [Turndown](https://github.com/domchristie/turndown) chained to the
  `RedmineFormatter` converter.
<table>
<thead>
<tr>
<th></th>
<th>Textile</th>
<th>Source→MD</th>
<th>Render→MD</th>
</tr>
</thead>
<tbody>
<tr>
<th>v3.4.6 r1</th>
<td>

```textile
 * a
 * b
```

</td>
<td>

```
  - a
  - b
```

</td>
<td>

```
  - a
  - b
```

</td>
</tr>
<tr>
<th>v3.4.7 r1</th>
<td>

```textile
 * a
 * b
```

</td>
<td>

```
  - a
  - b
```

</td>
<td>

```
  - a * b
```

</td>
</tr>
<tr>
<th>v3.4.7 r2</th>
<td>

```textile
* a
* b
```

</td>
<td>

```
  - a
  - b
```

</td>
<td>

```
  - a
  - b
```

</td>
</tr>
<tr>
<th>v3.4.7 diff r1 r2</th>
<td>

```diff
- * a
- * b
+* a
+* b
```

</td>
<td>
(empty)
</td>
<td>

```diff
-  - a * b
+  - a
+  - b
```

</td>
</tr>
</tbody>
</table>
