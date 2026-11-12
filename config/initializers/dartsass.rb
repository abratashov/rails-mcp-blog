Rails.application.config.dartsass.builds = { "active_admin.scss" => "active_admin.css" }
Rails.application.config.dartsass.build_options += [ "--quiet-deps", "--silence-deprecation=import" ]
