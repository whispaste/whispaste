// Geometry gate for the onboarding loops. Injected into a STAGED composition
// (scripts/stage.sh with GEOMETRY=1); it runs in headless Chrome, seeks the
// timeline every 5 frames and checks the rules declared by data attributes:
//   data-box="n"        container; data-in="n" children must lie inside it
//   data-pad="px"       inset a child must keep from its container (default 0)
//   data-group="g"      members of one group, unioned; data-within="n" centres
//                       the union in container n (±2 px)
//   data-circle="n"     circle; data-ring="n" ring with the same centre (±1 px)
//   data-center="n"     element whose centre must equal circle n (±1 px)
//   data-keep-in="n"    transformed box of the element lies inside the rounded
//                       contour of box n in every sampled frame (scale counts)
// Stage rule: every element with data-in or data-group stays inside the 920x576
// stage with an 8 px safety margin. Result: window.__geometry, and an Error is
// thrown on any violation so `hyperframes validate` reports it.
(function () {
  const TOL_CENTRE = 2;
  const TOL_RING = 1;
  const MARGIN = 8;
  const STAGE = { w: 920, h: 576 };
  const FPS = 30;

  function rect(el, root) {
    const r = el.getBoundingClientRect();
    const o = root.getBoundingClientRect();
    return { x: r.left - o.left, y: r.top - o.top, w: r.width, h: r.height,
      r: r.right - o.left, b: r.bottom - o.top, cx: r.left - o.left + r.width / 2,
      cy: r.top - o.top + r.height / 2 };
  }

  // Layout box: ignores CSS transforms, so scaled lines and tweened parts do
  // not shift containment or group centring. Rings and centres use rect().
  // Coordinates are absolute in the stage, also for nested positioned elements.
  function lay(el, root) {
    if (el === root) {
      return { x: 0, y: 0, w: root.offsetWidth, h: root.offsetHeight, r: root.offsetWidth, b: root.offsetHeight,
        cx: root.offsetWidth / 2, cy: root.offsetHeight / 2 };
    }
    // Absolute stage coordinates: offsets add up through nested positioned parents
    // (a bar inside the pill is placed relative to the pill).
    let x = 0, y = 0;
    for (let n = el; n && n !== root; n = n.offsetParent) { x += n.offsetLeft; y += n.offsetTop; }
    const w = el.offsetWidth, h = el.offsetHeight;
    return { x, y, w, h, r: x + w, b: y + h, cx: x + w / 2, cy: y + h / 2 };
  }

  function check(id, root) {
    const tl = window.__timelines[id];
    const fails = [];
    const q = (sel) => Array.from(root.querySelectorAll(sel));
    const byName = (attr, name) => q(`[${attr}="${name}"]`);
    const boxes = { stage: root };
    q("[data-box]").forEach((el) => (boxes[el.dataset.box] = el));
    const circles = {};
    q("[data-circle]").forEach((el) => (circles[el.dataset.circle] = el));
    const groups = {};
    q("[data-group]").forEach((el) => {
      (groups[el.dataset.group] = groups[el.dataset.group] || []).push(el);
    });
    const kids = q("[data-in]");
    const frames = [];
    for (let f = 0; f < 150; f += 5) frames.push(f);

    frames.forEach((f) => {
      tl.seek(f / FPS, false);
      const at = `t=${(f / FPS).toFixed(2)}s`;
      kids.forEach((el) => {
        const box = boxes[el.dataset.in];
        if (!box) return fails.push(`${at} missing box ${el.dataset.in}`);
        const pad = parseFloat(el.dataset.pad || "0");
        const b = lay(box, root);
        const c = lay(el, root);
        if (c.x < b.x + pad - 0.5 || c.r > b.r - pad + 0.5 || c.y < b.y + pad - 0.5 || c.b > b.b - pad + 0.5) {
          fails.push(`${at} ${el.id || el.className || el.tagName} outside ${el.dataset.in} (pad ${pad})`);
        }
      });
      Object.keys(groups).forEach((g) => {
        const members = groups[g].map((el) => lay(el, root));
        const ux = Math.min(...members.map((m) => m.x));
        const uy = Math.min(...members.map((m) => m.y));
        const ur = Math.max(...members.map((m) => m.r));
        const ub = Math.max(...members.map((m) => m.b));
        const within = groups[g][0].dataset.within;
        if (within) {
          const b = lay(boxes[within], root);
          const dx = (ux + ur) / 2 - (b.x + b.r) / 2;
          const dy = (uy + ub) / 2 - (b.y + b.b) / 2;
          if (Math.abs(dx) > TOL_CENTRE || Math.abs(dy) > TOL_CENTRE) {
            fails.push(`${at} group ${g} off-centre in ${within} by dx=${dx.toFixed(1)} dy=${dy.toFixed(1)}`);
          }
          if (ux < b.x || ur > b.r || uy < b.y || ub > b.b) {
            fails.push(`${at} group ${g} exceeds ${within}`);
          }
        }
      });
      // A ring with data-ring-set="a,b" must be concentric with the nearest of
      // those circles, except while it travels between them (strictly between).
      q("[data-ring-set]").forEach((ring) => {
        const rr = rect(ring, root);
        const names = ring.dataset.ringSet.split(",");
        const cs = names.map((n) => rect(circles[n], root));
        const ys = cs.map((c) => c.cy);
        const between = rr.cy > Math.min(...ys) + TOL_RING && rr.cy < Math.max(...ys) - TOL_RING;
        if (between) return;
        const near = cs.reduce((a, c) => (Math.hypot(c.cx - rr.cx, c.cy - rr.cy) < Math.hypot(a.cx - rr.cx, a.cy - rr.cy) ? c : a));
        if (Math.abs(rr.cx - near.cx) > TOL_RING || Math.abs(rr.cy - near.cy) > TOL_RING) {
          fails.push(`${at} ring not concentric with its circle (dx=${(rr.cx - near.cx).toFixed(1)} dy=${(rr.cy - near.cy).toFixed(1)})`);
        }
      });
      // Overlap rule (layout is static, so checked once at t = 0): two checked
      // elements may not overlap, except a box and its own children (data-in),
      // or elements that carry data-overlap-ok (an intended overlap, e.g. a ring
      // on its circle, a clip on its board, a highlight behind text).
      if (f === 0) {
        const id = (el) => el.id || el.className || el.tagName;
        // Every visible element of the picture, except the inside of inline SVGs
        // (an svg counts as one element). Zero-area containers drop out below.
        const set = q("*")
          .filter((el) => el !== root && !(el.closest("svg") && el.tagName.toLowerCase() !== "svg"))
          .filter((el) => el.closest("#root") === root && !el.closest("script, style"))
          .map((el) => ({ el, r: lay(el, root) }))
          .filter((o) => o.r.w * o.r.h > 0);
        for (let i = 0; i < set.length; i++) {
          for (let j = i + 1; j < set.length; j++) {
            const a = set[i];
            const b = set[j];
            if (a.el.hasAttribute("data-overlap-ok") || b.el.hasAttribute("data-overlap-ok")) continue;
            // Containment: a child lies in its box, also through nested boxes.
            const chainOf = (el) => {
              const names = [];
              let box = el.dataset.in;
              while (box && !names.includes(box)) {
                names.push(box);
                const parent = q(`[data-box="${box}"]`)[0];
                box = parent ? parent.dataset.in : undefined;
              }
              return names;
            };
            if ((a.el.dataset.box && chainOf(b.el).includes(a.el.dataset.box)) ||
                (b.el.dataset.box && chainOf(a.el).includes(b.el.dataset.box))) continue;
            const ix = Math.min(a.r.r, b.r.r) - Math.max(a.r.x, b.r.x);
            const iy = Math.min(a.r.b, b.r.b) - Math.max(a.r.y, b.r.y);
            if (ix > 0.5 && iy > 0.5) {
              fails.push(`${at} overlap between ${id(a.el)} and ${id(b.el)} (${ix.toFixed(0)}x${iy.toFixed(0)} px)`);
            }
          }
        }
      }
      // A link joins two circle contours: data-link="a,b" on a bar means its top
      // end sits on circle a's bottom contour and its bottom end on circle b's top
      // contour (±1 px), both centred on the circle axis.
      q("[data-link]").forEach((el) => {
        const [na, nb] = el.dataset.link.split(",");
        const L = lay(el, root);
        const A = lay(circles[na], root);
        const B = lay(circles[nb], root);
        if (Math.abs(L.y - A.b) > TOL_RING || Math.abs(L.b - B.y) > TOL_RING) {
          fails.push(`${at} ${el.id} ends off the contours (top ${L.y} vs ${A.b}, bottom ${L.b} vs ${B.y})`);
        }
        if (Math.abs(L.cx - A.cx) > TOL_RING || Math.abs(L.cx - B.cx) > TOL_RING) {
          fails.push(`${at} ${el.id} not on the circle axis`);
        }
      });
      // Horizontal link: data-link-x="a,b" on a bar means its left end sits on the
      // right contour of a and its right end on the left contour of b (±1 px), and
      // it runs on the centre line of a.
      q("[data-link-x]").forEach((el) => {
        const [na, nb] = el.dataset.linkX.split(",");
        const L = lay(el, root);
        const A = lay(boxes[na], root);
        const B = lay(boxes[nb], root);
        if (Math.abs(L.x - A.r) > TOL_RING || Math.abs(L.r - B.x) > TOL_RING) {
          fails.push(`${at} ${el.id} ends off the contours (left ${L.x} vs ${A.r}, right ${L.r} vs ${B.x})`);
        }
        if (Math.abs(L.cy - A.cy) > TOL_RING || Math.abs(L.cy - B.cy) > TOL_RING) {
          fails.push(`${at} ${el.id} off the centre line`);
        }
      });
      // A badge sits outside its circle: its nearest point to the centre must be at
      // least radius + 2 px away, so it never touches or overlaps the contour.
      q("[data-badge]").forEach((el) => {
        const C = lay(circles[el.dataset.badge], root);
        const K = lay(el, root);
        const nx = Math.min(Math.max(C.cx, K.x), K.r);
        const ny = Math.min(Math.max(C.cy, K.y), K.b);
        const d = Math.hypot(nx - C.cx, ny - C.cy);
        if (d < C.w / 2 + 2) fails.push(`${at} ${el.id} collides with the contour of ${el.dataset.badge}`);
      });
      q("[data-center]").forEach((el) => {
        const e = rect(el, root);
        const target = circles[el.dataset.center];
        const cc = rect(target, root);
        if (Math.abs(e.cx - cc.cx) > TOL_RING || Math.abs(e.cy - cc.cy) > TOL_RING) {
          fails.push(`${at} ${el.id} not centred on ${el.dataset.center}`);
        }
      });
      // Visual containment: data-keep-in="n" means the element's transformed box
      // (getBoundingClientRect, so scale and tweens count) lies inside the rounded
      // contour of box n in every sampled frame. The contour is a rounded rect whose
      // corner radius is half the shorter layout side, scaled by the box's transform.
      q("[data-keep-in]").forEach((el) => {
        const box = boxes[el.dataset.keepIn];
        if (!box) return fails.push(`${at} missing box ${el.dataset.keepIn}`);
        const lb = lay(box, root);
        const t = rect(box, root);
        const base = Math.min(lb.w, lb.h) / 2;
        const rx = base * (t.w / lb.w);
        const ry = base * (t.h / lb.h);
        const c = rect(el, root);
        const inside = (px, py) => {
          const qx = Math.min(Math.max(px, t.x + rx), t.r - rx);
          const qy = Math.min(Math.max(py, t.y + ry), t.b - ry);
          return ((px - qx) / rx) ** 2 + ((py - qy) / ry) ** 2 <= 1.002;
        };
        const corners = [[c.x, c.y], [c.r, c.y], [c.x, c.b], [c.r, c.b]];
        if (!corners.every(([x, y]) => inside(x, y))) {
          fails.push(`${at} ${el.id || el.className} leaves the contour of ${el.dataset.keepIn}`);
        }
      });
      const inStage = q("[data-in], [data-group]");
      inStage.forEach((el) => {
        const r = lay(el, root);
        if (r.x < MARGIN || r.y < MARGIN || r.r > STAGE.w - MARGIN || r.b > STAGE.h - MARGIN) {
          fails.push(`${at} ${el.id || el.className} leaves the stage safety area`);
        }
      });
    });
    tl.seek(0, false);
    return fails;
  }

  window.addEventListener("load", () => {
    const root = document.getElementById("root");
    const id = root.dataset.compositionId;
    const fails = check(id, root);
    window.__geometry = { id, samples: 30, failures: fails };
    if (fails.length) {
      throw new Error(`GEOMETRY FAIL ${id}: ${fails.length} issue(s); first: ${fails.slice(0, 5).join(" | ")}`);
    }
    console.log(`GEOMETRY OK ${id}`);
  });
})();
