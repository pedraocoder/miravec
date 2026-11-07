"""Cruzamento espacial OVT x EDL: cobertura, indices e lacunas."""
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")

BASE = Path(__file__).resolve().parents[2] / "dados" / "tratados_py"
RAIO_PADRAO = 500        # metros
RAIOS_TESTE = (458, 500, 769)   # extremos da distancia media praticada pela GEVACZ
RAIO_TERRA = 6_371_000   # metros


def distancia_matriz(lat_a, lon_a, lat_b, lon_b):
    """Haversine vetorizada: devolve matriz (len(a) x len(b)) em metros."""
    la = np.radians(lat_a)[:, None]
    lo = np.radians(lon_a)[:, None]
    lb = np.radians(lat_b)[None, :]
    lob = np.radians(lon_b)[None, :]
    dlat, dlon = lb - la, lob - lo
    h = np.sin(dlat / 2) ** 2 + np.cos(la) * np.cos(lb) * np.sin(dlon / 2) ** 2
    return 2 * RAIO_TERRA * np.arcsin(np.sqrt(h))


def indices(grupo):
    """IPO e IDO conforme as formulas da GEVACZ."""
    examinadas = grupo.n_ovos.notna().sum()
    positivas = (grupo.n_ovos > 0).sum()
    ovos = grupo.n_ovos.sum()
    return pd.Series(
        {
            "examinadas": examinadas,
            "positivas": positivas,
            "ovos": ovos,
            "ipo": 100 * positivas / examinadas if examinadas else np.nan,
            "ido": ovos / positivas if positivas else np.nan,
        }
    )


def main():
    leituras = pd.read_csv(BASE / "leituras.csv")
    pontos = pd.read_csv(BASE / "pontos_edl.csv")

    # So conta como fonte de cobertura o ponto que tem EDL instalada E coordenada.
    fontes = pontos[(pontos.lat.notna()) & (pontos.qt_edl.fillna(0) > 0)].copy()

    armadilhas = (
        leituras[leituras.lat.notna()]
        .groupby("id_ovt")
        .agg(lat=("lat", "first"), lon=("lon", "first"),
             ds=("ds", "first"), bairro=("bairro", "first"))
        .reset_index()
    )

    dist = distancia_matriz(
        armadilhas.lat.values, armadilhas.lon.values,
        fontes.lat.values, fontes.lon.values,
    )
    armadilhas["dist_edl_m"] = dist.min(axis=1)
    mais_perto = dist.argmin(axis=1)
    armadilhas["edl_proxima"] = fontes.nome_pe.values[mais_perto]
    # EDLs dentro de 500 m, somando o peso de cada ponto
    armadilhas["edls_no_raio"] = [
        fontes.qt_edl.values[linha <= RAIO_PADRAO].sum() for linha in dist
    ]

    print("=" * 66)
    print("1. DISTANCIA DA ARMADILHA ATE A EDL MAIS PROXIMA")
    print("=" * 66)
    d = armadilhas.dist_edl_m
    print(f"armadilhas analisadas: {len(armadilhas)}")
    for q in (10, 25, 50, 75, 90):
        print(f"  p{q:<3d} {d.quantile(q/100):8.0f} m")
    print(f"  max  {d.max():8.0f} m")
    print()

    print("=" * 66)
    print("2. COBERTURA POR RAIO")
    print("=" * 66)
    for raio in RAIOS_TESTE:
        cob = (d <= raio).sum()
        print(f"  raio {raio:3d} m -> {cob:5d} cobertas "
              f"({100*cob/len(d):5.1f}%) | {len(d)-cob:5d} descobertas")
    print()

    print("=" * 66)
    print("3. COBERTURA POR DISTRITO (raio de 500 m)")
    print("=" * 66)
    armadilhas["coberta"] = armadilhas.dist_edl_m <= RAIO_PADRAO
    por_ds = armadilhas.groupby("ds").agg(
        armadilhas=("id_ovt", "size"),
        cobertas=("coberta", "sum"),
        dist_mediana=("dist_edl_m", "median"),
    )
    por_ds["cobertura_%"] = (100 * por_ds.cobertas / por_ds.armadilhas).round(1)
    edl_geo = fontes.groupby("ds").qt_edl.sum()
    edl_tot = pontos.groupby("ds").qt_edl.sum()
    por_ds["edl_geo"] = edl_geo
    por_ds["edl_total"] = edl_tot
    print(por_ds.to_string())
    print()

    print("=" * 66)
    print("4. INDICES POR CICLO (todos os distritos)")
    print("=" * 66)
    por_ciclo = leituras.groupby("ciclo").apply(indices)
    por_ciclo["ipo"] = por_ciclo.ipo.round(1)
    por_ciclo["ido"] = por_ciclo.ido.round(1)
    print(por_ciclo.to_string())
    print()

    print("=" * 66)
    print("5. INDICE x COBERTURA  (atencao ao vies, ver nota)")
    print("=" * 66)
    marcado = leituras.merge(
        armadilhas[["id_ovt", "coberta", "dist_edl_m"]], on="id_ovt", how="inner"
    )
    comp = marcado.groupby("coberta").apply(indices)
    comp["ipo"] = comp.ipo.round(1)
    comp["ido"] = comp.ido.round(1)
    comp.index = ["fora do raio", "dentro do raio"]
    print(comp.to_string())
    print()

    print("=" * 66)
    print("6. BAIRROS COM INDICE ALTO E NENHUMA EDL NO RAIO")
    print("=" * 66)
    bairro = marcado.groupby("bairro").apply(indices)
    cob_bairro = armadilhas.groupby("bairro").coberta.mean()
    bairro["cobertura"] = cob_bairro
    bairro = bairro[bairro.examinadas >= 50]
    lacuna = bairro[bairro.cobertura == 0].sort_values("ido", ascending=False)
    print(f"bairros com 50+ leituras: {len(bairro)} | "
          f"sem nenhuma EDL no raio: {len(lacuna)}")
    print()
    print(lacuna[["examinadas", "ipo", "ido", "cobertura"]].head(12).round(1).to_string())

    armadilhas.to_csv(BASE / "cobertura_armadilhas.csv", index=False)


if __name__ == "__main__":
    main()
