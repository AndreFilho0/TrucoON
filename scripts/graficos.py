# Gera os gráficos de resultados do README (SVG) a partir dos números medidos.
#   python3 scripts/graficos.py
# Os SVGs vão para docs/checkpoint-2/graficos e docs/checkpoint-3/graficos; o PNG
# (2×) sai de cada SVG com: rsvg-convert -z 2 -b white x.svg -o x.png
import os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
SURF="#ffffff"; INK="#0b0b0b"; INK2="#52514e"; GRID="#e6e5e0"; C1="#2a78d6"; C2="#eb6834"

def bar(x, y0, w, h):
    # retângulo com cantos de 4px só na ponta (topo), ancorado na linha de base
    r = min(4, w/2, h) if h > 0 else 0
    if h <= 0:
        return ""
    y = y0 - h
    return (f'M{x},{y0} L{x},{y+r} Q{x},{y} {x+r},{y} L{x+w-r},{y} '
            f'Q{x+w},{y} {x+w},{y+r} L{x+w},{y0} Z')

def chart(path, title, subtitle, groups, series, ymax, ystep, unit, note):
    W,H = 720, 414
    L,R,T,B = 64, 24, 116, 56
    pw, ph = W-L-R, H-T-B
    y0 = T+ph
    sc = lambda v: v/ymax*ph
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
         f'font-family="Inter, Segoe UI, Helvetica, Arial, sans-serif">',
         f'<rect width="{W}" height="{H}" fill="{SURF}"/>',
         f'<text x="{L-40}" y="30" font-size="17" font-weight="600" fill="{INK}">{title}</text>',
         f'<text x="{L-40}" y="52" font-size="13" fill="{INK2}">{subtitle}</text>']
    # legenda
    lx = L-40
    for name,color,_ in series:
        s.append(f'<rect x="{lx}" y="66" width="12" height="12" rx="3" fill="{color}"/>')
        s.append(f'<text x="{lx+18}" y="76.5" font-size="13" fill="{INK}">{name}</text>')
        lx += 18 + 7.4*len(name) + 24
    # grade e eixo
    v = 0
    while v <= ymax + 1e-9:
        y = y0 - sc(v)
        s.append(f'<line x1="{L}" x2="{W-R}" y1="{y}" y2="{y}" stroke="{GRID}" stroke-width="1"/>')
        s.append(f'<text x="{L-8}" y="{y+4}" font-size="12" fill="{INK2}" text-anchor="end">{v:g}</text>')
        v += ystep
    s.append(f'<text x="{L-8}" y="{T-16}" font-size="12" fill="{INK2}" text-anchor="end">{unit}</text>')
    gw = pw/len(groups); bw = min(56, gw*0.3); gap = 2
    for i,g in enumerate(groups):
        cx = L + gw*i + gw/2
        x = cx - (len(series)*bw + (len(series)-1)*gap)/2
        for name,color,vals in series:
            val = vals[i]; h = sc(val)
            if h > 0:
                s.append(f'<path d="{bar(x,y0,bw,h)}" fill="{color}"><title>{name} · {g}: {val:g} {unit}</title></path>')
            else:
                s.append(f'<line x1="{x}" x2="{x+bw}" y1="{y0-1}" y2="{y0-1}" stroke="{color}" stroke-width="2"/>')
            s.append(f'<text x="{x+bw/2}" y="{y0-h-6}" font-size="12.5" font-weight="600" fill="{INK}" text-anchor="middle">{val:g}</text>')
            x += bw + gap
        s.append(f'<text x="{cx}" y="{y0+20}" font-size="13" fill="{INK}" text-anchor="middle">{g}</text>')
    s.append(f'<line x1="{L}" x2="{W-R}" y1="{y0}" y2="{y0}" stroke="{INK2}" stroke-width="1"/>')
    s.append(f'<text x="{L-40}" y="{H-12}" font-size="11.5" fill="{INK2}">{note}</text>')
    s.append('</svg>')
    fname = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(fname), exist_ok=True)
    open(fname,"w").write("\n".join(s))

chart("checkpoint-2/graficos/latencia-transporte.svg",
      "Latência por pedido: socket TCP × RPC",
      "300 pedidos para cada um de 3 peers, mesmo caminho de código",
      ["Média","Mediana","p99"],
      [("Socket TCP (conexão por pedido)",C1,[143,133,203]),("RPC (:erpc)",C2,[28,27,56])],
      250, 50, "µs", "Fonte: V.transport_benchmark(300). Menor é melhor.")

chart("checkpoint-2/graficos/multicast-perdas-fifo.svg",
      "Multicast sem tratamento × canal confiável FIFO",
      "4 peers, 30 mensagens cada, 10% de perda e 0–60 ms de atraso",
      ["Perdidas","Duplicadas","Violações de FIFO"],
      [("ORDERING=none",C1,[50,0,28]),("ORDERING=fifo",C2,[0,0,0])],
      60, 10, "msgs", "Fonte: V.bench(30). Menor é melhor; o canal FIFO zera as três métricas.")

chart("checkpoint-3/graficos/ordem-total.svg",
      "Canal FIFO × ordem total com Lamport",
      "4 peers, 10% de perda e 0–60 ms de atraso; disputa de cadeira em 8 mesas",
      ["Posições fora de ordem","Mesas divergentes","Msgs por multicast"],
      [("ORDERING=fifo",C1,[116,8,4]),("ORDERING=total (Lamport)",C2,[0,0,20])],
      120, 20, "", "Fonte: V.bench(30) e S.seat_race(rooms: 8). O Lamport zera a divergência e paga com N + N² mensagens.")
