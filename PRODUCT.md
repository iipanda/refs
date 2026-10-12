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
The first landing page speaks to designers and developers who collect UI inspiration and use coding agents. The user requested a download button; the primary CTA now downloads the current Mac development build, and the secondary CTA explores the browser-local demonstration. The audience remains a working assumption, not a confirmed permanent preference; the audience question was presented during the initial landing-page task. The download CTA is an explicit user requirement.

## Stack
The repository is a Swift package with existing static HTML mocks. This preview is buildless HTML/CSS/JS in landing/, with self-hosted fonts and no framework runtime.
