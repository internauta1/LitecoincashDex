# LitecoinCash DEX Next — Privacy Notice

Version: 3 · 9 November 2026

## 1. This community distribution

LitecoinCash DEX Next is a community distribution of open-source wallet software. This notice describes this application and its community contributors. A local wallet is controlled by its user and does not create a custodial account with the community project.

The community information portal is [LitecoinCash Brasil](https://litecoincash.com.br/). It describes itself as independent of the protocol website [litecoincash.net](https://litecoincash.net/). Links to these resources do not make them the operator of every service used by this application. For community questions, use the [published contact channels](https://litecoincash.com.br/comunidade). Never send a seed phrase, private key, wallet password or RPC password to a contact channel.

## 2. Local wallet information

Wallet names, encrypted wallet material, asset selections, addresses, transaction history and preferences are handled by the application and its local Komodo DeFi Framework engine. The local engine communicates with the interface over loopback RPC. Local encryption and operating-system protection reduce some risks; they do not protect a compromised device, an unprotected export or a lost backup.

Using a local wallet does not make its public blockchain activity private. Exports and backups can contain sensitive information and are controlled by the user. Removing an application, cache or local record does not remove transactions from a blockchain or guarantee physical erasure of backup copies.

## 3. Connections to other services

The software can contact blockchain nodes, Electrum servers, DEX peers and relays, market-price providers, transaction-history services, NFT and anti-spam services, and optional third-party payment services. Depending on the request, a provider may receive an IP address, asset/network identifier, public wallet address, transaction identifier or request timing. DEX orders and blockchain transactions can be publicly visible when those features are used.

Some current integrations use services on gleec.com subdomains. They remain third-party technical providers; replacing the application's logo does not transfer their infrastructure or policies to LitecoinCash Brasil. Provider websites, fiat ramps, hardware wallets and external community platforms have their own terms and data practices. Opening one of their pages may involve additional cookies or data collection outside this application.

## 4. Diagnostics and analytics

This codebase includes diagnostic logs, performance measurements and analytics integrations. What is collected or transmitted depends on the build, settings and configured provider. Diagnostic redaction is not a reason to publish a log without reviewing it. Do not submit seeds, passwords, private keys, signed transaction material or unnecessary personal information with a support request. Logging and analytics settings do not stop the network requests needed for features you choose to use.

Disposable validation builds use an approved no-funds profile and disabled trading. A separate private manual-validation build can enable real trading, with a new wallet created and controlled only by its user. Both use isolated directories and loopback RPC on port 17993 and cannot run together. Process and crash metadata can be collected for validation; private wallet credentials must not be supplied to an operator. A successful test does not establish that every integration is available or that every possible diagnostic record has been audited.

## 5. Contacts, choices and updates

Use the application's available settings to manage optional features. For questions about this distribution, consult the [community channels](https://litecoincash.com.br/comunidade); describe the feature and software version without disclosing wallet secrets. A third-party provider handles requests concerning its own service. Website policies apply to use of the website and must not be treated as a complete description of this wallet's data flows.

This notice is bundled with this distribution. The application does not silently replace it with an upstream project's legal notice. Updated community documents require a new reviewed distribution; the consent interface identifies the actual text presented. No claim of universal legal compliance or a guaranteed deletion/retention period is made here.
