module github.com/ayman708-UX/torrserver_flutter/tool/go-shim

go 1.25.7

require (
	golang.org/x/mobile v0.0.0-20240404185917-48f886f4a866
	server v0.0.0-00010101000000-000000000000
)

replace (
	github.com/anacrolix/torrent v1.59.1 => github.com/tsynik/torrent v1.2.28
	github.com/anacrolix/upnp v0.1.4 => github.com/tsynik/upnp v0.1.5
	server => ./torrserver-src/server
)
