import UniformTypeIdentifiers

enum BrowserFileType {
    /// Local formats that browsers are useful picker targets for. Text-like formats such as
    /// JSON, XML, and TXT remain AppCat-supported file types, but browsers are intentionally not
    /// offered for them because the file picker is choosing an editor, not a read-only preview.
    static let browserPreviewContentTypeIdentifiers = [
        "public.html",
        "public.xhtml",
        "public.svg-image",
        "com.adobe.pdf",
        "com.apple.webarchive",
        "com.apple.web-internet-location",
        "public.url",
        "com.microsoft.internet-shortcut",
        "org.ietf.mhtml",
    ]

    static let appCatSupportedBaseContentTypeIdentifiers = orderedUnique(
        browserPreviewContentTypeIdentifiers + [
            "public.xml",
            "public.json",
            "public.plain-text",
        ]
    )

    static let developerContentTypeIdentifiers = [
        "ua.com.rmarinsky.appcat.env-config",
        "public.yaml",
        "public.source-code",
        "public.script",
        "public.shell-script",
        "public.python-script",
        "public.ruby-script",
        "public.perl-script",
        "public.php-script",
        "public.c-source",
        "public.c-plus-plus-source",
        "public.c-header",
        "public.c-plus-plus-header",
        "public.objective-c-source",
        "public.objective-c-plus-plus-source",
        "public.swift-source",
        "com.netscape.javascript-source",
        "com.apple.property-list",
        "com.apple.applescript.text",
    ]

    static let genericFileContentTypeIdentifiers = [
        "public.data",
    ]

    static let developerFilePatterns = [
        "env",
        "env.local",
        "env.development",
        "env.production",
        "env.staging",
        "env.test",
        "env.example",
        "env.sample",
        "local",
        "development",
        "production",
        "staging",
        "test",
        "example",
        "sample",
        "azure.yaml",
        "yaml",
        "yml",
        "toml",
        "ini",
        "cfg",
        "conf",
        "config",
        "properties",
        "plist",
        "editorconfig",
        "gitignore",
        "gitattributes",
        "gitconfig",
        "gitmodules",
        "dockerignore",
        "npmrc",
        "nvmrc",
        "yarnrc",
        "tool-versions",
        "bashrc",
        "bash_profile",
        "bash_aliases",
        "profile",
        "zprofile",
        "zshenv",
        "zshrc",
        "zlogin",
        "zlogout",
        "fish",
        "sh",
        "bash",
        "zsh",
        "csh",
        "ksh",
        "service",
        "timer",
        "socket",
        "target",
        "mount",
        "automount",
        "path",
        "dockerfile",
        "dockerfile.dev",
        "dockerfile.prod",
        "compose.yaml",
        "compose.yml",
        "docker-compose.yaml",
        "docker-compose.yml",
        "makefile",
        "gnumakefile",
        "cmakelists.txt",
        "jenkinsfile",
        "justfile",
        "taskfile",
        "taskfile.yaml",
        "taskfile.yml",
        "procfile",
        "gemfile",
        "rakefile",
        "brewfile",
        "vagrantfile",
        "caddyfile",
        "nginx.conf",
        "httpd.conf",
        "sql",
        "graphql",
        "tf",
        "tfvars",
        "hcl",
        "nomad",
        "gradle",
        "kts",
        "pom",
        "xml",
        "json",
        "jsonc",
        "lock",
        "md",
        "markdown",
        "txt",
        "log",
    ]

    static let browserReadableDefaultHandlerContentTypeIdentifiers = [
        "public.html",
        "public.xhtml",
        "public.svg-image",
        "com.apple.webarchive",
        "com.apple.web-internet-location",
        "public.url",
        "com.microsoft.internet-shortcut",
        "org.ietf.mhtml",
    ]

    static let supportedContentTypeIdentifiers = orderedUnique(
        appCatSupportedBaseContentTypeIdentifiers + developerContentTypeIdentifiers + genericFileContentTypeIdentifiers
    )

    static let defaultHandlerContentTypeIdentifiers = orderedUnique(
        browserReadableDefaultHandlerContentTypeIdentifiers + developerContentTypeIdentifiers + genericFileContentTypeIdentifiers
    )

    static let defaultHandlerStatusContentTypeIdentifiers = orderedUnique(
        browserReadableDefaultHandlerContentTypeIdentifiers + [
            "ua.com.rmarinsky.appcat.env-config",
            "public.yaml",
            "public.source-code",
            "public.shell-script",
            "public.swift-source",
            "com.apple.property-list",
        ]
    )

    static var defaultHandlerContentTypes: [UTType] {
        let explicitTypes = defaultHandlerContentTypeIdentifiers.compactMap(UTType.init)
        let extensionTypes = developerFilePatterns.compactMap { UTType(filenameExtension: $0) }
        return orderedUnique(explicitTypes + extensionTypes, by: \.identifier)
    }

    static var defaultHandlerStatusContentTypes: [UTType] {
        defaultHandlerStatusContentTypeIdentifiers.compactMap(UTType.init)
    }

    static func fileMatchTokens(for url: URL) -> Set<String> {
        guard url.isFileURL else { return [] }

        let name = url.lastPathComponent.lowercased()
        let extensionName = url.pathExtension.lowercased()
        var tokens: Set<String> = [name]

        if !extensionName.isEmpty {
            tokens.insert(extensionName)
        }

        if name.hasPrefix(".") {
            tokens.insert(String(name.dropFirst()))
        }

        return tokens.filter { !$0.isEmpty }
    }

    static func isBrowserReadableFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        let identifiers = Set(browserPreviewContentTypeIdentifiers)
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if identifiers.contains(contentType.identifier) {
                return true
            }
            if browserPreviewContentTypeIdentifiers
                .compactMap(UTType.init)
                .contains(where: { contentType.conforms(to: $0) })
            {
                return true
            }
        }

        return !fileMatchTokens(for: url).isDisjoint(with: [
            "html", "htm", "xhtml", "xht", "svg", "pdf", "webarchive", "webloc", "url",
            "mhtml", "mht",
        ])
    }

    static func isDeveloperFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        if !fileMatchTokens(for: url).isDisjoint(with: Set(developerFilePatterns)) {
            return true
        }

        let identifiers = Set(developerContentTypeIdentifiers)
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }

        if identifiers.contains(contentType.identifier) {
            return true
        }

        return developerContentTypeIdentifiers
            .compactMap(UTType.init)
            .contains { contentType.conforms(to: $0) }
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func orderedUnique<T, Key: Hashable>(_ values: [T], by keyPath: KeyPath<T, Key>) -> [T] {
        var seen = Set<Key>()
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
