# Apple Foundations

Swift package for shared native application behavior, localization, and common
platform integrations. It must not contain product-specific UI or business
logic.

```sh
make build
make test
make format-check
```

Add the package through Xcode or Swift Package Manager and import the required
product: `AvgeekLocalizationCore`, `AvgeekLocalizationUI`, or
`AvgeekNetworking`.

Bundled with DNSDeck so a public checkout builds without private dependencies.

[Repository](../../README.md)
