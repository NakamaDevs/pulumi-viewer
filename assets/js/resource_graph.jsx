// xyflow graph of Pulumi resources, laid out with ELK, mounted as a LiveView hook.
import {createRoot} from "react-dom/client"
import {useEffect, useState} from "react"
import {ReactFlow, Background, Controls, MiniMap, Handle, Position, MarkerType} from "@xyflow/react"
import ELK from "elkjs/lib/elk.bundled.js"

const elk = new ELK()
const W = 220, H = 64

const PALETTE = {aws: "#f59e0b", pulumi: "#8b5cf6", kubernetes: "#3b82f6", random: "#10b981", command: "#64748b"}
const color = pkg => PALETTE[pkg] || "#0ea5e9"

// Node look of the dashboard graph: a card with a round icon tinted by provider,
// the name and the type. The selected node gets the accent ring.
function ResourceNode({data, selected}) {
  const c = color(data.package)
  return (
    <div className={`flex items-center gap-2 rounded-lg border bg-base-100 px-2.5 py-2 text-xs w-[220px] shadow-sm ${selected ? "border-primary ring-2 ring-primary/40" : "border-base-300"}`}>
      <Handle type="target" position={Position.Left} className="!bg-base-300 !border-0" />
      <span className="flex size-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-white" style={{background: c}}>
        {(data.package || "?").slice(0, 3)}
      </span>
      <div className="min-w-0">
        <div className="font-semibold truncate text-[13px]">{data.protect ? "🔒 " : ""}{data.label}</div>
        <div className="opacity-70 truncate font-mono text-[11px]">{data.type}</div>
      </div>
      <Handle type="source" position={Position.Right} className="!bg-base-300 !border-0" />
    </div>
  )
}

const nodeTypes = {resource: ResourceNode}
const EDGE = {
  parent: {stroke: "#a3a3a3", strokeDasharray: "4 4"},
  dependency: {stroke: "#7c5ce0"},
  provider: {stroke: "#8b5cf6", strokeDasharray: "2 3"},
}

async function layout(graph) {
  const res = await elk.layout({
    id: "root",
    layoutOptions: {"elk.algorithm": "layered", "elk.direction": "RIGHT", "elk.spacing.nodeNode": "24", "elk.layered.spacing.nodeNodeBetweenLayers": "60"},
    children: graph.nodes.map(n => ({id: n.id, width: W, height: H})),
    edges: graph.edges.map(e => ({id: e.id, sources: [e.source], targets: [e.target]})),
  })
  const pos = Object.fromEntries(res.children.map(c => [c.id, {x: c.x, y: c.y}]))
  return {
    nodes: graph.nodes.map(n => ({...n, width: W, height: H, position: pos[n.id] || n.position})),
    edges: graph.edges.map(e => ({...e, style: EDGE[e.data.kind], markerEnd: {type: MarkerType.ArrowClosed}})),
  }
}

function Graph({graph, onSelect}) {
  const [laid, setLaid] = useState(null)
  useEffect(() => { layout(graph).then(setLaid) }, [graph])
  if (!laid) return <div className="p-6 opacity-60">Laying out {graph.nodes.length} resources…</div>
  return (
    <ReactFlow colorMode={document.documentElement.dataset.theme || "system"} nodes={laid.nodes} edges={laid.edges} nodeTypes={nodeTypes} fitView minZoom={0.05}
               onNodeClick={(_, n) => onSelect(n.id)} proOptions={{hideAttribution: false}}>
      <Background gap={16} />
      <MiniMap pannable zoomable nodeColor={n => color(n.data.package)} />
      <Controls />
    </ReactFlow>
  )
}

export const ResourceGraph = {
  mounted() {
    this.root = createRoot(this.el)
    this.render()
  },
  updated() { this.render() },
  destroyed() { this.root.unmount() },
  render() {
    const graph = JSON.parse(this.el.dataset.graph)
    this.root.render(<Graph graph={graph} onSelect={urn => this.pushEvent("select", {urn})} />)
  },
}
