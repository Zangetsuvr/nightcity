import { useMemo } from 'react'
import { ink } from '../theme.ts'

// The city behind everything: three layers of towers against a sodium-lit
// haze, with a few lit windows on the nearest layer. Generated from a fixed
// seed so it looks the same every launch.

function random (seed: number) {
  let s = seed
  return () => {
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  }
}

interface Tower { x: number, w: number, h: number, spire: boolean }

function towers (seed: number, count: number, minH: number, maxH: number): Tower[] {
  const r = random(seed)
  const out: Tower[] = []
  let x = -20
  for (let i = 0; i < count && x < 1100; i++) {
    const w = 24 + r() * 70
    out.push({ x, w, h: minH + Math.pow(r(), 1.6) * (maxH - minH), spire: r() > 0.86 })
    x += w + r() * 6
  }
  return out
}

function path (list: Tower[], base: number) {
  return list.map(t => {
    const top = base - t.h
    const spire = t.spire ? ` L${t.x + t.w / 2 - 2},${top} L${t.x + t.w / 2},${top - 40} L${t.x + t.w / 2 + 2},${top}` : ''
    return `M${t.x},${base} L${t.x},${top}${spire} L${t.x + t.w},${top} L${t.x + t.w},${base} Z`
  }).join(' ')
}

export default function Skyline () {
  const far = useMemo(() => towers(7, 40, 140, 330), [])
  const mid = useMemo(() => towers(19, 34, 90, 250), [])
  const near = useMemo(() => towers(41, 26, 40, 190), [])
  const windows = useMemo(() => {
    const r = random(83)
    const lit: Array<{ x: number, y: number }> = []
    for (const t of near) {
      for (let y = 400 - t.h + 10; y < 392; y += 9) {
        for (let x = t.x + 5; x < t.x + t.w - 6; x += 8) {
          if (r() > 0.93) lit.push({ x, y })
        }
      }
    }
    return lit
  }, [near])

  return (
    <svg className="skyline" viewBox="0 0 1080 400" preserveAspectRatio="xMidYMax slice" aria-hidden="true">
      <defs>
        <linearGradient id="haze" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={ink.smog} stopOpacity="0"/>
          <stop offset="0.55" stopColor="#5A2D3E" stopOpacity="0.55"/>
          <stop offset="1" stopColor={ink.sodium} stopOpacity="0.45"/>
        </linearGradient>
      </defs>
      <rect x="0" y="0" width="1080" height="400" fill="url(#haze)"/>
      <path d={path(far, 400)} fill="#2C2648" opacity="0.8"/>
      <path d={path(mid, 400)} fill="#211D3A"/>
      <path d={path(near, 400)} fill="#141127"/>
      {windows.map((w, i) => (
        <rect key={i} x={w.x} y={w.y} width="3" height="4" fill={i % 7 === 0 ? ink.rose : ink.sodium} opacity={0.55 + (i % 3) * 0.15}/>
      ))}
    </svg>
  )
}
