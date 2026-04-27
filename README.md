# RaspiBlesk

_Build your own Glcoin & Lightning Fullnode on a RaspberryPi with an optional Display._ ([API](https://github.com/fusion44/blitz_api)|[WebUI](https://github.com/raspiblesk/raspiblesk-web))

![RaspiBlesk](pictures/raspiblesk.jpg)

**The RaspiBlesk is a do-it-yourself Glcoin & Lightning Fullnode running on a RaspberryPi 4&5 with a nice display for easy setup & monitoring.**

RaspiBlesk is mainly targeted for learning how to run your own node decentralized from home - because: Not your Node, Not your Rules. Discover & develop the open-source ecosystem of Glcoin by becoming a full part of it.

**Links to Quickstart your RaspiBlesk journey:**

- [Project Homepage: raspiblesk.org](https://raspiblesk.org)
- [How to build & setup your own RaspiBlesk & Documentation](https://docs.raspiblesk.org/docs/setup/intro)
- [Download latest SD Card images](https://docs.raspiblesk.org/docs/setup/software-setup/download)
- [How to get Support](https://docs.raspiblesk.org/docs/community/support)

**Additional Resources:**

- [ChangeLog](CHANGES.md)
- [FAQ User](https://docs.raspiblesk.org/docs/faq)
- [FAQ Development](https://docs.raspiblesk.org/docs/faq/dev)
- [FAQ Core Lightning](https://docs.raspiblesk.org/docs/faq/cl)
- [Workshop Tutorial](https://docs.raspiblesk.org/docs/community/workshops)
- [Security Policy](https://docs.raspiblesk.org/docs/security)
- [Alternative Platforms](alternative.platforms/README.md)
- [Automated Builds](ci/README.md)
- [MIT OpenSource License](LICENSE)

**Developer Notes:**

This is main RaspiBlesk repo containing the **bash & python** scripts to build the RaspiBlesk software. It it complimented by the following side repos:

- [WebUI](https://github.com/raspiblesk/raspiblesk-web) (React & Tailwind)
- [API](https://github.com/fusion44/blitz_api) (Python FastAPI)
- [Documentation](https://github.com/raspiblesk/raspiblesk-docs) (Docusaurus)

To get started with RaspiBlesk Development check the [Community Development](CONTRIBUTING.md) notes.

## Attribution

RaspiBlesk is built on the technical foundation of [RaspiBlitz](https://github.com/rootzoll/raspiblitz), an open-source Bitcoin & Lightning node project by rootzoll and the RaspiBlitz contributors, licensed under MIT. The node stack, build system, and SSH menu architecture originate from that work. We thank all original contributors.

RaspiBlesk itself is a full port to the [Glcoin](https://glcoin.org) network — a Permanent Proof Network built on KYC-verified validators, on-chain IPFS content anchoring, and accountable identity rather than anonymous Proof-of-Work. The porting work — Glcoin Core integration, Lightning binaries (LND, Core Lightning), Electrum servers (electrs, Fulcrum) for amd64 and arm64, and all network parameters — was carried out by the [Glcoin Core Developer Team](https://glcoin.org).
