# Aether and HCL

HCL (HashiCorp Configuration Language, the language of Terraform, Nomad and
Packer) is the most capable static configuration language in common use. This
page compares it with an Aether configuration: a `.ae` file whose trailing
blocks read like configuration and run as code. It is the HCL-specific entry
point. The general argument is in [config-is-code.md](config-is-code.md), and
the survey of other formats (YAML, TOML, HOCON, CUE, Pkl, Starlark) is in
[aether-embedded-in-host-applications.md](aether-embedded-in-host-applications.md).

## What HCL gets right

HCL is not "just config", and a comparison that pretends it is would be
wrong.

- **Repetition is built in.** `count` and `for_each` repeat a resource over a
  number, a set or a map; `dynamic` blocks repeat a nested block; `for`
  expressions (`[for s in var.services : s.name]`) build lists and maps.
- **Values compute.** Conditional expressions (`cond ? a : b`), `locals`, and
  a library of built-in functions (string, collection, encoding, network,
  date, and file functions such as `templatefile`). Since Terraform 1.8 a
  provider can add functions of its own.
- **Inputs are typed and validated.** A `variable` has a `type` constraint
  (`object({...})`, `list(...)`, `map(...)`), a `default`, and `validation`
  blocks whose conditions run before anything is planned.
- **Changes are reviewed before they happen.** `terraform plan` shows what
  an apply would create, change and destroy, against the recorded state of
  the real infrastructure.
- **The ecosystem is enormous.** Thousands of providers, and a format every
  infrastructure team already reads.

## Where it stops

What HCL leaves out is deliberate, but it is what a growing configuration
eventually needs:

- **No functions of your own.** You compose the built-in functions (and
  provider-defined ones); you cannot name a computation and reuse it. Modules
  share structure, not logic.
- **Expressions, not statements.** A conditional is a ternary. "Create this
  resource only in production" is `count = var.env == "prod" ? 1 : 0`, and a
  conditional nested block is a `dynamic` block over a one- or zero-element
  list.
- **A second language inside the first.** `templatefile` renders its own
  template syntax (`%{ for }`, `%{ if }`, `${}`), with its own rules, in a
  separate file.
- **The "how" lives elsewhere.** HCL describes *what*; a provider written in
  Go implements *how*. Two languages, two repositories, two release cycles,
  and a schema between them that both must agree on
  ([aether-embedded-in-host-applications.md](aether-embedded-in-host-applications.md),
  "Accept the boundary").
- **Several namespaces for one idea.** `variable`, `locals`, `output`, `data`
  and module inputs and outputs each carry values, with their own rules for
  where they can be read.

## The same configuration, side by side

A service gateway with a list of backends. Each backend gets a health check;
production adds TLS and a second replica; the backend's config file is
rendered from a template.

### HCL

```hcl
variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "backends" {
  type = map(object({
    port = number
    path = string
  }))
}

locals {
  replicas = var.env == "prod" ? 2 : 1
}

resource "gateway_route" "backend" {
  for_each = var.backends

  name     = each.key
  port     = each.value.port
  replicas = local.replicas
  config   = templatefile("${path.module}/backend.tpl", {
    name = each.key
    path = each.value.path
  })

  health_check {
    path     = "/healthz"
    interval = 10
  }

  dynamic "tls" {
    for_each = var.env == "prod" ? [1] : []
    content {
      cert = "/etc/tls/${each.key}.pem"
    }
  }
}
```

plus `backend.tpl` in template syntax, plus the provider (Go) that implements
`gateway_route`.

### Aether

```aether,fragment
import gateway (routes, route, port, replicas, health_check, tls, config)
import std.os

extern exit(code: int)

backend_config(name: string, path: string) -> string {
    return "name = ${name}\nroot = ${path}\n"
}

// One backend's route, a function of its own: HCL has no way to name one.
backend(env: string, name: string, p: int, path: string) {
    route(name) {
        port(p)
        replicas(if env == "prod" { 2 } else { 1 })
        config(backend_config(name, path))
        health_check("/healthz", 10)
        if env == "prod" {
            tls("/etc/tls/${name}.pem")
        }
    }
}

main() {
    env = os.getenv("ENV")
    if env != "dev" && env != "prod" {
        println("ENV must be dev or prod")
        exit(1)
    }
    routes {
        backend(env, "api", 8080, "/srv/api")
        backend(env, "web", 8081, "/srv/web")
    }
}
```

One file, one language. A backend is a function, the condition an `if`, the
template a function, and `gateway` (the library that implements `route`) is
written in Aether too, or is a C library the `.ae` binds to. The trailing
blocks are the [builder DSL](closures-and-builder-dsl.md): `route(name) { ... }`
reads like a block of settings and is a call with a closure. The backends
could as well come from a file read at startup, looped over with
`for i in 0..n`.

## Typed, validated inputs

HCL's `variable` blocks with `type` and `validation` have a counterpart in
`std.schema`: a declared record whose parse is the validation, and whose
failure lists every problem with its field and a code.

```aether,fragment
import std.schema

backend = schema.record() {
    schema.field("port", schema.INT) {
        schema.min(1)
        schema.max(65535)
    }
    schema.field("path", schema.STR) {
        schema.present()
        schema.pattern("prefix:/")
    }
    schema.field("env", schema.STR) {
        schema.one_of("dev,prod")
    }
}
values, errors = schema.parse(backend, input)
```

The same declaration projects to JSON Schema (`schema.to_json_schema`), so an
editor or another service can check the input before it reaches the program
([schema-projection-roadmap.md](schema-projection-roadmap.md)).

## Reviewing a configuration before it runs

`terraform plan` is HCL's strongest operational feature, and Aether has no
equivalent of a plan against recorded infrastructure state. What it has for
review:

- `ae check config.ae` type-checks without building or running.
- `ae inspect config.ae` prints what a script declares without running it:
  its imports, the capabilities they need (`fs`, `net`, `os`), its exports.
- An operator's configuration can be built as a library with only the
  capabilities it is granted (`--emit=lib --with=fs`), so a configuration
  that tries to open a socket does not compile
  ([containment-sandbox.md](containment-sandbox.md),
  [hide-and-seal.md](hide-and-seal.md)).

## HOCON, briefly

HOCON reached the same place as HCL from the other side: it added includes,
substitutions and merge rules to JSON, and still has no conditionals or
loops. Growing a static format does not reach a programming language; it
reaches a large specification. The table in
[aether-embedded-in-host-applications.md](aether-embedded-in-host-applications.md)
puts it with YAML and CUE under "monstrous spec".

## When to pick which

Pick HCL when:

- you need Terraform's providers: the ecosystem is the deciding factor, and
  no `.ae` file replaces a mature cloud provider;
- you want plan-and-apply against recorded state;
- the people editing configuration should need nothing but a text editor.
  Aether needs its toolchain installed to check or run a configuration, and
  that is a real cost.

Pick Aether when:

- your configuration keeps growing features and is turning into a weak
  programming language: functions, loops over computed inputs, branches on
  the environment;
- your program's own settings are what is being configured, so the "how"
  and the "what" can live in one language and one release;
- operators' configurations must run sandboxed, with only the capabilities
  you grant.
