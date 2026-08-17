# Meet InterlinedList: A Native iOS App for Sharing Messages, Lists, and Docs

I've been heads-down on a project I'm genuinely excited to finally start talking about: **InterlinedList**, a native iOS app that sits on top of the [interlinedlist.com](https://interlinedlist.com) backend. If you've followed along here for a while, you know I have a soft spot for two things — clean, well-architected software, and the messy, human act of *sharing what you're working on*. InterlinedList is where those two collide.

So let's take a walk through it. I'll show you the three things the app is really built around — **messages**, **lists**, and **documents** — and then, because it's the little details that make an app feel like *yours*, I'll wrap up with a quick note on flipping the whole thing between light and dark.

Grab a coffee. Here we go.

## The one-sentence version

InterlinedList is a social space for people who think in lists. You post short messages to a feed, you keep structured lists (with real, typed columns — not just checkboxes), and you write longer-form documents in Markdown. Follow people, watch their lists, join organizations, cross-post out to the wider social web if you want to. It's built in pure SwiftUI, targets iOS 17+, and leans on nothing but Apple's own frameworks — no third-party dependency sprawl to babysit.

The app opens into four simple sections along the top — **Home**, **Lists**, **Documents**, and your **Profile** — plus an envelope for direct messages and a bell for notifications. That's the whole map. Let's dig into the three that matter most.

## Messages: the feed you actually post to

The **Home** tab is your feed. It's the beating heart of the app and the fastest way to get a feel for it.

![The InterlinedList home feed on iOS](01-feed.png)
*The Home feed — messages from you and the people you follow, all in one scroll.*

Tap the compose button and you get a genuinely capable little editor:

- **Write your post** with a live character counter so you always know how much room you've got left.
- **Public or private** with a single toggle — decide per-post whether the world sees it or just you.
- **Attach photos and video** right from the composer.
- **Tag it** so it's findable later.
- **Schedule it** for later if you're not ready to ship it this second.

![The InterlinedList compose screen](02-compose.png)
*The composer: a public/private toggle, photo and video attachments, tags, and scheduling — all in one sheet.*

Once a post is out in the feed, it behaves the way you'd expect a modern social surface to behave. You can **reply** and follow the thread, **repost** something worth boosting, **edit** your own posts, and give a post a **dig** — my favorite little bit of the vocabulary here, InterlinedList's take on the "like." Link previews get pulled in automatically, images and video render inline, and long posts collapse behind a tidy "Read more."

And if you're a subscriber, there's a nice power-user flourish: **cross-posting**. From the composer you can fan a single message out to Mastodon, Bluesky, LinkedIn, and X at the same time it publishes on InterlinedList. Write once, land everywhere. (There's even a "post the link as a first comment" option for the LinkedIn crowd who care about that sort of thing — and yes, I see you, I *am* one of you.)

Oh, and that envelope icon up top? That's your **direct messages** — private one-to-one threads, with an unread badge so you don't miss anything.

## Lists: structured, nested, and genuinely useful

Here's where InterlinedList earns its name. A **list** here isn't just a stack of bullet points — it's a small, structured thing with **typed columns you define yourself**.

Head to the **Lists** tab, tap the **+**, and you can spin up a **New List** or a **New Folder**. Folders nest, lists live inside folders, and lists can even nest inside *other* lists — so you can model something as loose as "books to read" or as involved as a little multi-level catalog without leaving the app.

![The InterlinedList Lists tab on iOS](03-lists.png)
*The Lists tab — folders and structured lists, nested however you like.*

The part I love is the **schema editor**. Every list has a schema — a set of properties (columns) with real types, labels, ordering, required/optional flags, help text, the works. Long-press any list and you'll find **Rename / Edit**, **Edit Schema**, and **Delete**. Define your columns once and every row you add follows that shape. It's the difference between a note that *says* it's organized and data that actually *is*.

A few more things worth knowing:

- **Public lists** — flip a list public and it's shareable and browsable beyond your own account.
- **Watchers** — people can watch a list and follow along as it changes.
- **Connections** — lists can be linked to one another, so related collections stay related.

It's the closest thing I've found to "a tiny database that doesn't feel like a database," and it lives right in your pocket.

## Documents: Markdown for the longer thoughts

Sometimes a message is too short and a list is the wrong shape. That's what **Documents** are for.

The **Documents** tab is your space for longer-form writing, all in **Markdown**. Tap the **+** and you can create a **New Document**, start from a **Template**, or make a **New Folder** to keep things tidy. Just like lists, document folders nest, so you can build up a real little library instead of a flat pile of files.

![The InterlinedList Documents tab on iOS](04-documents.png)
*The Documents tab — Markdown docs and folders for the longer-form thinking.*

Under the hood each document is Markdown, edited in-app and rendered cleanly for reading — headers, formatting, inline images and all. Documents can be **public or private**, they support **collaborators** so you're not writing in a silo, and subscribers get **templates** to copy a good starting structure into a fresh doc instead of staring at a blank page.

Feed for the quick stuff, lists for the structured stuff, documents for the thought-out stuff. Three tools, one app, and they all speak to the same account.

## Oh — and a quick note so you can change the theme as you desire, to either your system, light, or dark!

Because of course you can. I wasn't about to ship an app in 2026 that forces one appearance on you. InterlinedList respects your **system** setting by default, but if you'd rather nail it to **light** or **dark** regardless of what the OS is doing, that's a two-second change. Here's how.

### Setting the theme in InterlinedList

1. Open the app and tap your **Profile** (the avatar on the far right of the top bar).
2. Tap the **gear / Settings** icon in the top-left of the Profile screen.
3. Under the **Appearance** section at the top, you'll see a **Theme** picker.
4. Choose one of:
   - **System** — follow whatever your iPhone is set to (this is the default, and it'll switch with your device automatically, sundown included).
   - **Light** — always light, no matter what iOS is doing.
   - **Dark** — always dark, same deal.

![The InterlinedList Settings screen with the Appearance theme picker](05-settings-theme.png)
*Settings → Appearance → Theme — pick System, Light, or Dark and the whole app follows.*

That's it. The change applies **instantly** — the entire app re-tints the moment you tap. Because InterlinedList saves your choice to your **account** rather than just this one device, your preference **follows you**: sign in on another iPhone and it comes right along with you.

One small design note I'll own up to, since this blog is as much about the *how* as the *what*: "System" is stored as *no explicit preference*. When you pick Light or Dark, the app hands SwiftUI a `preferredColorScheme` and locks it in; when you pick System, it steps out of the way entirely and lets iOS drive. Small detail, but it's the kind of thing that makes an app feel like it's cooperating with the platform instead of fighting it.

## Wrapping up

That's the quick tour: **messages** for the feed, **lists** for the structured stuff, **documents** for the long-form, and a theme picker so the whole thing looks the way *you* want it to. There's plenty more under the surface — organizations, following and follow-requests, notification preferences, moderation controls, OAuth sign-in — but this is the core, and honestly it's the core I use every day.

I'll be writing more about how it's put together on the inside (the SwiftUI architecture, the API client, the caching layer, all the parts I nerd out about) in follow-up posts. For now, go make a list, write a doc, post something to the feed — and set it to dark mode while you're at it.

Cheers,
Adron
