# Who's on My Wi-Fi

A tiny native Mac app that shows how many devices share the Wi-Fi you're connected to, what they're called, and when each one arrived. No router login, no account, nothing sent anywhere.

## Download

1. Go to [Releases](../../releases/latest) and download `WhosOnMyWiFi.zip`.
2. Unzip it and move **Who's on My Wi-Fi** to your Applications folder.
3. Open it once. macOS will refuse ("Apple could not verify…"), because the app isn't paid-notarized by Apple; choose **Done**. Then open **System Settings → Privacy & Security**, scroll down, choose **Open Anyway**, enter your password and click **Open**. You only do this once.
4. Allow **Local Network** access when asked. Without it the app can't see other devices.

Requires macOS 13 or later. Works on Apple Silicon and Intel Macs.

## Use

Join a Wi-Fi network (turn off any VPN) and open the app. It scans straight away and again every minute while it's open; **Refresh now** scans immediately.

You'll see:

- **Devices on your Wi-Fi right now**, including your own Mac. The router itself isn't counted.
- **Busy hours**: the count over the last 24 hours.
- **Devices**: each device's name when it announces one (for example "Priyas-iPhone"), otherwise **Unknown device**, with its IP and hardware (MAC) address and when it was first and last seen since the app opened.

## What the count means

The count is the number of devices that answered. Treat it as a minimum:

- Sleeping phones and devices that ignore pings can be missed.
- Many phones hide their name and use a private, changing hardware address. A name is chosen by the device's owner and says nothing reliable about who they are.
- **Big networks:** on networks with more than 1,024 addresses, the app scans only the 1,024 nearest your Mac and says so ("Scanned 1,024 of 65,534 addresses").
- **Networks that hide devices:** most public Wi-Fi (cafés, airports, hotels) stops devices seeing each other. There the app shows only your Mac and tells you the network may be hiding devices. No app on a guest device can count those networks; only the network's owner can, from the router.

## Privacy

- Device names and addresses are kept in memory only and vanish when you quit.
- Only the counts over time are saved, for 24 hours, in `~/Library/Application Support/Whos On My WiFi/history.json`.
- The app only talks to devices on your local network: it pings them and asks your router for device names. It has no servers, accounts or tracking.

## Be considerate

Only scan networks you're allowed to use. The app pings each address on the network once a minute, which some network owners don't welcome. Respect the rules of the network you're on.

## Build from source

Needs Apple's command-line tools (`xcode-select --install`). No third-party dependencies.

```sh
sh test.sh            # run the checks
sh build.sh           # build "build/Who's on My Wi-Fi.app" for Apple Silicon and Intel
sh build.sh --zip     # also create build/WhosOnMyWiFi.zip for a release
sh test.sh --live     # scan the network you're on from the terminal
```

## License

[MIT](LICENSE) © 2026 Être Research
