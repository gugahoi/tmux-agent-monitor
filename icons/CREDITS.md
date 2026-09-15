# Icon credits & trademarks

The **state dots** (`agent-*.svg` / `.png`) are original to this project.

The **agent marks** (`logo-*.svg`, and the `logo-*`/`badge-*` PNGs derived from
them) reproduce each project's own logo, used **nominatively** — solely to
identify that agent in notifications. Each logo remains the property of its
owner; inclusion here is not affiliation or endorsement. The circular tile and
the corner state dot are added by `generate.sh`.

| agent    | mark source (fetched)                                                   | owner / project |
|----------|------------------------------------------------------------------------|-----------------|
| claude   | `https://claude.ai/favicon.svg`                                        | Anthropic       |
| opencode | `https://opencode.ai/favicon.svg`                                      | opencode (SST)  |
| pi       | `https://pi.dev/logo-auto.svg`                                         | earendil-works  |

To refresh a mark, re-download its source over the matching `logo-<agent>.svg`
and run `./generate.sh`. If any owner would prefer their mark not be bundled,
replace `logo-<agent>.svg` with a neutral lettermark and regenerate — the rest
of the pipeline is unchanged.
