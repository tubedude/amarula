# AGENTS.md

This is an application written using Elixir.

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

  ```elixir
  i = 0
  mylist = ["blue", "green"]
  mylist[i]
  ```

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access:

  ```elixir
  i = 0
  mylist = ["blue", "green"]
  Enum.at(mylist, i)
  ```

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression:

  ```elixir
  # INVALID: we are rebinding inside the `if` and the result never gets assigned
  if connected?(socket) do
    socket = assign(socket, :val, val)
  end

  # VALID: we rebind the result of the `if` to a new variable
  socket =
    if connected?(socket) do
      assign(socket, :val, val)
    end
  ```

- **Avoid nested `if` statements** - they quickly become unreadable. Instead, use `cond` for multiple conditions or `case` with pattern matching:

  ```elixir
  # AVOID: nested if statements
  if condition1 do
    if condition2 do
      if condition3 do
        :result
      end
    end
  end

  # PREFER: use cond for clearer flow
  cond do
    condition1 and condition2 and condition3 -> :result
    condition1 and condition2 -> :other_result
    condition1 -> :another_result
    true -> :default
  end

  # OR: use case with pattern matching
  case {condition1, condition2, condition3} do
    {true, true, true} -> :result
    {true, true, false} -> :other_result
    _ -> :default
  end
  ```

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors

- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets

- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)

- Don't use `String.to_atom/1` on user input (memory leak risk)

- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards

- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`

- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

- **Pattern matching order matters**: In `case` expressions, always order patterns from most specific to least specific. Generic patterns like `{:ok, _bindings, new_state}` should come after specific patterns like `{:ok, :fail, _new_state}` to avoid unreachable code warnings

## Error handling

- **Prefer pattern matching over try/rescue**: Use `{:ok, result}` / `{:error, reason}` tuples with `case` instead of exceptions for flow control

  ```elixir
  # PREFER
  case File.read("config.json") do
    {:ok, content} -> process(content)
    {:error, reason} -> handle_error(reason)
  end

  # AVOID (unless truly exceptional)
  try do
    File.read!("config.json")
  rescue
    e -> handle_error(e)
  end
  ```

- Use the `!` versions of functions (e.g., `File.read!/1`) only when the error is truly exceptional and should crash the process

- **Let it crash**: Don't rescue errors unless you need observability/monitoring. Let supervisors handle process failures and restarts

- Variables defined inside `try/catch/rescue/after` blocks don't leak to outer context - always bind the result of the entire `try` expression:

  ```elixir
  result =
    try do
      risky_operation()
    rescue
      _ -> :error
    end
  ```