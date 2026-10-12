# Refs

<!-- impeccable:product-schema 1 -->

## Platform
web

This surface markets the native macOS Refs app; it does not replace its native UI.

## Product Purpose
Refs saves screenshots and videos of UI with their source app or website and a short note about what the user likes. Its local library can be read and managed by coding agents over MCP.

## Capabilities and Constraints
Verified in README.md and current Swift sources: area/window capture, silent screen recording, notes, automatic source metadata, source grouping, search, reference copying, local file storage and an MCP helper. macOS 14+ and Apple Silicon are the current build requirements. Browser source metadata requires per-browser Automation permission. Public download URL, pricing, hosted audience and release distribution are undecided. No fabricated customer claims.

## Brand Commitments
The name is Refs. Use the approved quotation icon and its yellow/charcoal palette. Preserve the current native app.

## Working Assumptions for This Surface
The first landing page speaks to designers and developers who collect UI inspiration and use coding agents. The first CTA explores a browser-local demonstration. These are working assumptions, not confirmed permanent product preferences; audience and CTA questions were presented during this task.

## Stack
The repository is a Swift package with existing static HTML mocks. This preview is buildless HTML/CSS/JS in landing/, with self-hosted fonts and no framework runtime.
