// xyflow graph of Pulumi resources, laid out with ELK, mounted as a LiveView hook.
import {createRoot} from "react-dom/client"
import {useEffect, useState} from "react"
import {ReactFlow, Background, Controls, MiniMap, Handle, Position, MarkerType} from "@xyflow/react"
import ELK from "elkjs/lib/elk.bundled.js"

const elk = new ELK()
const W = 220, H = 64

const PALETTE = {aws: "#f59e0b", pulumi: "#8b5cf6", kubernetes: "#3b82f6", random: "#10b981", command: "#64748b"}
const color = pkg => PALETTE[pkg] || "#0ea5e9"

function ResourceNode({data, selected}) {
  return (
    <div className={`rounded-lg border bg-base-100 px-3 py-2 shadow-sm text-xs w-[220px] ${selected ? "ring-2 ring-primary" : "border-base-300"}`}
         style={{borderLeft: `4px solid ${color(data.package)}`}}>
      <Handle type="target" position={Position.Left} className="!bg-base-300" />
      <div className="font-semibold truncate">{data.protect ? "🔒 " : ""}{data.label}</div>
      <div className="opacity-60 truncate font-mono">{data.type}</div>
      <Handle type="source" position={Position.Right} className="!bg-base-300" />
    </div>
  )
}

const nodeTypes = {resource: ResourceNode}
const EDGE = {
  parent: {stroke: "#94a3b8", strokeDasharray: "4 4"},
  dependency: {stroke: "#0ea5e9"},
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
