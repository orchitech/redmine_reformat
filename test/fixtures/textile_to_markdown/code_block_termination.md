# Correct code

``` ruby
puts "clear skies"
puts "but users rely on Redmine to make them clear"
```

# Unbalanced tags - `</pre>` before `</code>`

``` ruby
puts "users often close pre before code"
```

# Unclosed `</code>` tag

``` ruby
puts "why bother to close code when I close the outter pre?"
```

# Real code tag inside pre

```
<response>
  <code>XX</code>
</response>
<response><code class="foo">YY</code></response>
```

# Termination by end of file `</pre>`

``` ruby
puts "someone's life is too short for writing ending tags at the end of text"
```
