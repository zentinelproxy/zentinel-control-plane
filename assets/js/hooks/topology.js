import * as d3 from "../../vendor/d3.min.js"

const NODE_COLORS = {
  service: { enabled: "#6366f1", disabled: "#94a3b8" },
  upstream_group: { healthy: "#22c55e", degraded: "#f59e0b" },
  auth_policy: { active: "#8b5cf6" },
  certificate: { active: "#eab308", expiring_soon: "#f97316", expired: "#ef4444" },
  middleware: { enabled: "#06b6d4", disabled: "#94a3b8" },
  target: { default: "#a3a3a3" }
}

const NODE_RADIUS = {
  service: 24,
  upstream_group: 20,
  auth_policy: 16,
  certificate: 16,
  middleware: 16,
  target: 8
}

const EDGE_COLORS = {
  upstream: "#6366f1",
  auth: "#8b5cf6",
  tls: "#eab308",
  middleware: "#06b6d4",
  target: "#a3a3a3"
}

const Topology = {
  mounted() {
    this.svg = null
    this.simulation = null

    const data = JSON.parse(this.el.dataset.topology)
    this.el.innerHTML = ""
    this.renderGraph(data)

    this.handleEvent("topology-data", (data) => {
      this.renderGraph(data)
    })

    this._resizeHandler = () => this.handleResize()
    window.addEventListener("resize", this._resizeHandler)
  },

  destroyed() {
    if (this.simulation) this.simulation.stop()
    window.removeEventListener("resize", this._resizeHandler)
  },

  handleResize() {
    if (this.simulation) {
      const data = this._lastData
      if (data) this.renderGraph(data)
    }
  },

  renderGraph(data) {
    this._lastData = data

    const width = this.el.clientWidth
    const height = this.el.clientHeight

    // Clear previous
    this.el.innerHTML = ""
    if (this.simulation) this.simulation.stop()

    const nodes = this.buildNodes(data)
    const links = this.buildLinks(data, nodes)

    if (nodes.length === 0) {
      this.el.innerHTML = '<div class="flex items-center justify-center h-full text-base-content/50">No services configured yet.</div>'
      return
    }

    const svg = d3.select(this.el)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height])

    const g = svg.append("g")

    // Zoom
    const zoom = d3.zoom()
      .scaleExtent([0.3, 3])
      .on("zoom", (event) => g.attr("transform", event.transform))

    svg.call(zoom)

    // Arrow markers
    const defs = svg.append("defs")
    Object.keys(EDGE_COLORS).forEach(type => {
      defs.append("marker")
        .attr("id", `arrow-${type}`)
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 20)
        .attr("refY", 0)
        .attr("markerWidth", 6)
        .attr("markerHeight", 6)
        .attr("orient", "auto")
        .append("path")
        .attr("d", "M0,-5L10,0L0,5")
        .attr("fill", EDGE_COLORS[type])
    })

    // Links
    const link = g.append("g")
      .selectAll("line")
      .data(links)
      .join("line")
      .attr("stroke", d => EDGE_COLORS[d.edge_type] || "#999")
      .attr("stroke-opacity", 0.5)
      .attr("stroke-width", d => d.edge_type === "upstream" ? 2 : 1.5)
      .attr("marker-end", d => `url(#arrow-${d.edge_type})`)

    // Nodes
    const node = g.append("g")
      .selectAll("g")
      .data(nodes)
      .join("g")
      .attr("cursor", d => d.type === "target" ? "default" : "pointer")
      .call(d3.drag()
        .on("start", (event, d) => {
          if (!event.active) this.simulation.alphaTarget(0.3).restart()
          d.fx = d.x
          d.fy = d.y
        })
        .on("drag", (event, d) => {
          d.fx = event.x
          d.fy = event.y
        })
        .on("end", (event, d) => {
          if (!event.active) this.simulation.alphaTarget(0)
          d.fx = null
          d.fy = null
        }))

    // Draw node shapes
    node.each(function(d) {
      const el = d3.select(this)
      const r = NODE_RADIUS[d.type] || 12
      const color = getNodeColor(d)

      if (d.type === "service") {
        el.append("rect")
          .attr("x", -r).attr("y", -r * 0.7)
          .attr("width", r * 2).attr("height", r * 1.4)
          .attr("rx", 4)
          .attr("fill", color)
          .attr("stroke", d3.color(color).darker(0.5))
          .attr("stroke-width", 1.5)
      } else if (d.type === "upstream_group") {
        el.append("circle")
          .attr("r", r)
          .attr("fill", color)
          .attr("stroke", d3.color(color).darker(0.5))
          .attr("stroke-width", 1.5)
      } else if (d.type === "auth_policy") {
        el.append("polygon")
          .attr("points", diamondPoints(r))
          .attr("fill", color)
          .attr("stroke", d3.color(color).darker(0.5))
          .attr("stroke-width", 1.5)
      } else if (d.type === "target") {
        el.append("circle")
          .attr("r", r)
          .attr("fill", color)
          .attr("stroke", d3.color(color).darker(0.3))
          .attr("stroke-width", 1)
      } else {
        el.append("rect")
          .attr("x", -r).attr("y", -r)
          .attr("width", r * 2).attr("height", r * 2)
          .attr("rx", 3)
          .attr("fill", color)
          .attr("stroke", d3.color(color).darker(0.5))
          .attr("stroke-width", 1.5)
      }

      // Label
      el.append("text")
        .attr("dy", r + 14)
        .attr("text-anchor", "middle")
        .attr("font-size", d.type === "target" ? "9px" : "11px")
        .attr("fill", "currentColor")
        .attr("class", "text-base-content/70")
        .text(d.name.length > 20 ? d.name.slice(0, 18) + "..." : d.name)
    })

    // Click handler
    node.on("click", (event, d) => {
      if (d.type !== "target") {
        this.pushEvent("navigate", { type: d.type, id: d.id })
      }
    })

    // Tooltip on hover
    node.append("title").text(d => {
      let tip = `${d.type}: ${d.name}\nStatus: ${d.status}`
      if (d.metadata) {
        Object.entries(d.metadata).forEach(([k, v]) => {
          if (v != null && typeof v !== "object") tip += `\n${k}: ${v}`
        })
      }
      return tip
    })

    // Force simulation
    this.simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(links).id(d => d.id).distance(120))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(d => (NODE_RADIUS[d.type] || 12) + 20))
      .on("tick", () => {
        link
          .attr("x1", d => d.source.x)
          .attr("y1", d => d.source.y)
          .attr("x2", d => d.target.x)
          .attr("y2", d => d.target.y)

        node.attr("transform", d => `translate(${d.x},${d.y})`)
      })
  },

  buildNodes(data) {
    const nodes = []

    ;(data.services || []).forEach(s => nodes.push({...s}))
    ;(data.upstream_groups || []).forEach(g => {
      nodes.push({...g})
      // Add target sub-nodes
      ;(g.metadata?.targets || []).forEach(t => {
        nodes.push({
          id: `target-${t.id}`,
          name: `${t.host}:${t.port}`,
          type: "target",
          status: "default",
          metadata: { weight: t.weight }
        })
      })
    })
    ;(data.auth_policies || []).forEach(a => nodes.push({...a}))
    ;(data.certificates || []).forEach(c => nodes.push({...c}))
    ;(data.middlewares || []).forEach(m => nodes.push({...m}))

    return nodes
  },

  buildLinks(data, nodes) {
    const nodeIds = new Set(nodes.map(n => n.id))
    return (data.edges || []).filter(e =>
      nodeIds.has(e.source) && nodeIds.has(e.target)
    ).map(e => ({...e}))
  }
}

function getNodeColor(d) {
  const colors = NODE_COLORS[d.type] || {}
  return colors[d.status] || colors.default || "#94a3b8"
}

function diamondPoints(r) {
  return `0,${-r} ${r},0 0,${r} ${-r},0`
}

export default Topology
