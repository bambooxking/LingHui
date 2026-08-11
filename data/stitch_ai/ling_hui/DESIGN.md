---
name: Ling Hui
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#3b494b'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#6a7a7b'
  outline-variant: '#b9cacb'
  surface-tint: '#006970'
  primary: '#006970'
  on-primary: '#ffffff'
  primary-container: '#00f0ff'
  on-primary-container: '#006970'
  inverse-primary: '#00dbe9'
  secondary: '#5400c3'
  on-secondary: '#ffffff'
  secondary-container: '#7000ff'
  on-secondary-container: '#ddcdff'
  tertiary: '#5c5f61'
  on-tertiary: '#ffffff'
  tertiary-container: '#d8dadc'
  on-tertiary-container: '#5c5f61'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#7df4ff'
  primary-fixed-dim: '#00dbe9'
  on-primary-fixed: '#002022'
  on-primary-fixed-variant: '#004f54'
  secondary-fixed: '#e9ddff'
  secondary-fixed-dim: '#d1bcff'
  on-secondary-fixed: '#23005b'
  on-secondary-fixed-variant: '#5700c9'
  tertiary-fixed: '#e0e3e5'
  tertiary-fixed-dim: '#c4c7c9'
  on-tertiary-fixed: '#191c1e'
  on-tertiary-fixed-variant: '#444749'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.4'
  body-base:
    fontFamily: Geist
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  body-sm:
    fontFamily: Geist
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  code-label:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1'
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 64px
  max-width: 1440px
---

## Brand & Style
The design system for this product centers on the intersection of advanced technology and ethereal "magic." The brand personality is professional yet visionary—evoking the feeling of a pristine, futuristic laboratory where AI processes images with surgical precision and artistic soul.

The aesthetic follows a **Tech-Minimalist** approach with **Glassmorphic** accents. It prioritizes vast white space and structural clarity to offset the complexity of AI workflows. Every interaction should feel like operating a high-end holographic interface: lightweight, responsive, and illuminated. The emotional response is one of calm confidence and limitless creative potential.

## Colors
The palette is rooted in a "High-Key" light mode to maintain a sense of laboratory cleanliness.

- **Primary (Electric Cyan):** Used for interactive states, progress indicators, and "active" AI pulses. It represents the energy of the processing engine.
- **Secondary (Digital Violet):** Used sparingly for deep-link accents or secondary AI functions, providing a hint of mystery and depth.
- **Surface & Backgrounds:** We use a range of ultra-light grays (#F8FAFC to #F1F5F9) to create soft layering without the harshness of pure white.
- **Glows:** Accent colors are frequently applied as low-opacity box-shadows (blooms) to simulate light emitting from the screen.

## Typography
The typographic scale emphasizes technical clarity and futuristic geometry.

- **Headlines:** Space Grotesk provides a geometric, slightly "tech" feel that remains highly readable. Use tight letter-spacing for large displays to create a premium, editorial look.
- **Body:** Geist is used for its exceptional neutrality and developer-centric precision, ensuring that complex settings and tooltips are legible.
- **Labels:** JetBrains Mono is utilized for metadata, coordinates, and AI parameters, reinforcing the "precision tool" aspect of the platform. All-caps styling is preferred for top-level labels.

## Layout & Spacing
The layout follows a **Fluid Grid** logic within a fixed container. 

- **Desktop:** 12-column grid with generous 64px outer margins to allow the UI to "breathe." Gutters are kept wide (24px) to emphasize the minimalist structure.
- **Mobile:** Switches to a 4-column grid with 16px margins. 
- **Rhythm:** All spacing (padding, margins) must be multiples of 4px. Use larger gaps (48px+) between major sections to maintain the minimalist "gallery" feel. 
- **Sidebars:** Tool panels should be anchored to the right/left using 100vh height, creating a "cockpit" feel for the image processing workspace.

## Elevation & Depth
Depth is created through **Glassmorphism** and **Luminous Outlines** rather than traditional heavy shadows.

- **Level 1 (Base):** Solid light gray surfaces.
- **Level 2 (Panels):** Semi-transparent white (60-80% opacity) with a `backdrop-filter: blur(12px)`.
- **Level 3 (Modals/Popovers):** Higher transparency with a subtle 1px border colored at 20% of the Primary Cyan. 
- **Shadows:** Avoid black shadows. Use "Ambient Glows"—very soft, large-radius blurs using the primary cyan at 5-10% opacity to suggest the element is hovering and powered by light.

## Shapes
The shape language is "Soft-Tech." 

- **Containers:** Standard cards and panels use a 0.5rem (8px) radius.
- **Interactive Elements:** Buttons and input fields use a more pronounced 1rem (16px) radius to make them feel inviting and "squishy" yet modern.
- **Micro-elements:** Tags and status indicators use a full-pill shape. 
- **Borders:** All borders should be 1px wide. For active states, use a "Glow Border" which is a 1px solid primary color paired with a 2px outer spread of the same color at 30% opacity.

## Components

- **Buttons:** 
  - *Primary:* Solid Cyan background with white text. On hover, add a subtle outer glow.
  - *Ghost:* 1px Cyan border, transparent background. Fill becomes 10% Cyan on hover.
- **Input Fields:** Minimalist underlines or very light gray fills. When focused, the border glows Primary Cyan and the label shifts to the Mono font.
- **AI Processing Chips:** Use pill-shaped containers with a slight shimmer animation (left-to-right gradient sweep) to indicate "thinking" or "active" states.
- **Image Cards:** No visible borders by default. On hover, a 1px Cyan border appears and the image slightly scales up within its container.
- **Icons:** Use thin-stroke (1.5pt) linear icons. Key actions (like 'Generate' or 'Enhance') should feature a dual-tone style using both Primary and Secondary colors.
- **Scrollbars:** Hidden or ultra-thin (2px) Cyan lines that only appear on interaction, maintaining the clean workspace aesthetic.