# UX Design Guidelines

## 1. Color System

### Primary Palette
| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Primary Blue | `#2563EB` | 37, 99, 235 | CTAs, links, primary actions |
| Primary Dark | `#1D4ED8` | 29, 78, 216 | Hover states, emphasis |
| Primary Light | `#3B82F6` | 59, 130, 246 | Backgrounds, highlights |

### Secondary Palette
| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Secondary Teal | `#0D9488` | 13, 148, 136 | Secondary actions, accents |
| Secondary Dark | `#0F766E` | 15, 118, 110 | Hover on secondary |

### Neutral Palette
| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Gray 900 | `#111827` | 17, 24, 39 | Headings, primary text |
| Gray 700 | `#374151` | 55, 65, 81 | Body text |
| Gray 500 | `#6B7280` | 107, 114, 128 | Secondary text, icons |
| Gray 300 | `#D1D5DB` | 209, 213, 219 | Borders, dividers |
| Gray 100 | `#F3F4F6` | 243, 244, 246 | Backgrounds, cards |
| White | `#FFFFFF` | 255, 255, 255 | Cards, inputs, page background |

### Semantic Colors
| Name | Hex | Usage |
|------|-----|-------|
| Success | `#059669` | Success states, confirmations |
| Warning | `#D97706` | Warnings, cautions |
| Error | `#DC2626` | Errors, destructive actions |
| Info | `#0284C7` | Information, tips |

### Color Usage Rules
- Primary color should appear no more than 60% of the visible UI
- Use white space and gray backgrounds to let primary elements stand out
- Never use pure black (#000000) — use Gray 900 instead
- Error red should never exceed 10% of total screen real estate

---

## 2. Typography

### Font Family
```
Primary: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif
Monospace: "JetBrains Mono", "Fira Code", Consolas, monospace
```

### Type Scale
| Token | Size | Line Height | Weight | Usage |
|-------|------|-------------|--------|-------|
| Display | 48px | 1.1 | 700 | Hero headlines |
| H1 | 36px | 1.2 | 700 | Page titles |
| H2 | 28px | 1.25 | 600 | Section headers |
| H3 | 22px | 1.3 | 600 | Subsection headers |
| H4 | 18px | 1.4 | 600 | Card titles |
| Body Large | 18px | 1.6 | 400 | Lead paragraphs |
| Body | 16px | 1.6 | 400 | Standard text |
| Body Small | 14px | 1.5 | 400 | Secondary text |
| Caption | 12px | 1.4 | 500 | Labels, timestamps |
| Overline | 11px | 1.3 | 600 | Categories, tags (uppercase) |

### Font Rules
- Body text max width: 65 characters (~600px at 16px)
- Minimum touch target text: 14px
- Minimum caption text: 12px
- Letter spacing for uppercase text: 0.05em
- Letter spacing for body: 0 (default)

---

## 3. Icon System

### Icon Library
- Primary: Lucide Icons (MIT license, consistent 24px grid)
- Alternative: Heroicons (outline style for navigation)

### Icon Sizes
| Name | Size | Usage |
|------|------|-------|
| xs | 16px | Inline with text, compact lists |
| sm | 20px | Form inputs, small buttons |
| md | 24px | Standard UI elements (default) |
| lg | 32px | Feature highlights, empty states |
| xl | 48px | Onboarding illustrations |

### Icon Guidelines
- Always use a single consistent stroke width (1.5px or 2px)
- icons should be optically centered within their grid
- Use `currentColor` for monochrome icons
- Minimum touch area for icon buttons: 44x44px

### Spacing with Icons
- Icon + Text gap: 8px (sm), 12px (md), 16px (lg)
- Icon-only button padding: 12px minimum

---

## 4. Spacing System

### Base Unit
```
Base unit: 4px
```

### Spacing Scale
| Token | Value | Usage |
|-------|-------|-------|
| space-0 | 0px | Tight grouping |
| space-1 | 4px | Icon gaps, tight padding |
| space-2 | 8px | Input padding, small gaps |
| space-3 | 12px | Button padding, card padding |
| space-4 | 16px | Standard padding, gaps |
| space-5 | 20px | Section gaps |
| space-6 | 24px | Card padding, section padding |
| space-8 | 32px | Large gaps |
| space-10 | 40px | Section separators |
| space-12 | 48px | Page section margins |
| space-16 | 64px | Major section dividers |

### Component Spacing
| Component | Padding | Gap |
|-----------|---------|-----|
| Button (default) | 12px 20px | 8px between buttons |
| Button (compact) | 8px 16px | 4px between buttons |
| Card | 24px | 16px between cards |
| Input | 12px 16px | - |
| Modal | 32px | 24px between sections |
| List Item | 16px | 0px (use dividers) |

### Grid System
- Desktop: 12-column grid, 24px gutters
- Tablet: 8-column grid, 20px gutters
- Mobile: 4-column grid, 16px gutters
- Max content width: 1280px
- Safe area on mobile: 16px horizontal padding

---

## 5. Animation & Motion

### Duration Scale
| Token | Duration | Usage |
|-------|----------|-------|
| instant | 0ms | State changes (disabled, etc.) |
| fast | 100ms | Micro-interactions (hover, press) |
| base | 200ms | Standard transitions |
| slow | 300ms | Emphasis animations |
| deliberate | 500ms | Page transitions, complex animations |

### Easing Functions
```css
--ease-out: cubic-bezier(0.16, 1, 0.3, 1);      /* Exit animations */
--ease-in: cubic-bezier(0.7, 0, 0.84, 0);       /* Enter animations */
--ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);  /* Symmetric animations */
--ease-bounce: cubic-bezier(0.34, 1.56, 0.64, 1); /* Playful elements */
```

### Motion Rules
- Hover transitions: 100ms ease-out
- Button press: scale(0.98), 100ms
- Modal enter: fade + slide up 24px, 300ms ease-out
- Modal exit: fade + slide down 16px, 200ms ease-in
- Page transitions: 300ms ease-in-out
- Loading spinners: continuous 1s linear loop
- Skeleton pulse: 1.5s ease-in-out infinite

### Animation Restrictions
- Never animate layout shifts that cause content reflow
- Respect `prefers-reduced-motion` media query
- Maximum animation duration: 500ms for any single element
- Avoid animation on large area backgrounds

### Micro-interactions
| Element | Trigger | Animation |
|---------|---------|-----------|
| Button | Hover | Background darken 10%, 100ms |
| Button | Active | scale(0.98), 100ms |
| Link | Hover | Color shift to Primary Dark, 100ms |
| Card | Hover | translateY(-2px), shadow increase, 200ms |
| Input | Focus | Border color to Primary, ring 2px Primary/20%, 150ms |
| Checkbox | Toggle | scale bounce on check, 200ms |

---

## 6. Shadow System

### Shadow Tokens
| Token | Value | Usage |
|-------|-------|-------|
| shadow-sm | 0 1px 2px rgba(0,0,0,0.05) | Subtle elevation |
| shadow-base | 0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06) | Cards, inputs |
| shadow-md | 0 4px 6px rgba(0,0,0,0.1), 0 2px 4px rgba(0,0,0,0.06) | Dropdowns, modals |
| shadow-lg | 0 10px 15px rgba(0,0,0,0.1), 0 4px 6px rgba(0,0,0,0.05) | Popovers, tooltips |
| shadow-xl | 0 20px 25px rgba(0,0,0,0.1), 0 10px 10px rgba(0,0,0,0.04) | Dialogs, overlays |

### Shadow Usage
- Use shadow-sm for rest state of elevated elements
- Use shadow-md for dropdowns and popovers
- Use shadow-lg for modals and overlays
- On hover, elevate one level (e.g., shadow-base → shadow-md)
- Always include backdrop blur for overlays: `backdrop-blur(8px)`

---

## 7. Border Radius

### Radius Tokens
| Token | Value | Usage |
|-------|-------|-------|
| radius-none | 0px | Sharp edges, data tables |
| radius-sm | 4px | Small inputs, badges |
| radius-base | 8px | Buttons, cards, inputs |
| radius-md | 12px | Modal content, larger cards |
| radius-lg | 16px | Hero sections |
| radius-full | 9999px | Pills, avatars, checkboxes |

---

## 8. Accessibility

- Color contrast ratio: minimum 4.5:1 for normal text, 3:1 for large text
- Focus indicators: 2px solid Primary with 2px offset
- Touch targets: minimum 44x44px
- Motion: respect `prefers-reduced-motion`
- Never convey information through color alone — always pair with icon or text

---

## Quick Reference Card

```
COLORS:    Primary #2563EB | Gray-700 #374151 | Success #059669
FONTS:     Body 16px/1.6 | H1 36px/1.2 | Caption 12px
SPACING:   Base 4px | Standard 16px | Section 48px
ANIMATION: Fast 100ms | Base 200ms | Slow 300ms
SHADOW:    Card shadow-base | Modal shadow-lg
RADIUS:    Button radius-base (8px) | Pill radius-full
```