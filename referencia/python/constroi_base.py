"""Monta a base unificada do MIRAVEC a partir dos tres arquivos do MVP.

Saidas em dados_tratados/:
  leituras.csv  - uma linha por armadilha por ciclo, com coordenada
  pontos_edl.csv - uma linha por ponto estrategico, com peso em EDLs
"""
import re
import warnings
from pathlib import Path

import pandas as pd

warnings.filterwarnings("ignore")

# Caminhos relativos a raiz do repositorio, como no pipeline em R.
RAIZ = Path(__file__).resolve().parents[2]
ORIGEM = RAIZ / "dados" / "brutos"
SAIDA = RAIZ / "dados" / "tratados_py"


def localizar(padrao):
    """Acha o arquivo pelo padrao do nome, como faz o pipeline em R."""
    achados = sorted(ORIGEM.glob(padrao))
    if not achados:
        raise SystemExit(
            f"Nenhum arquivo em {ORIGEM} casa com '{padrao}'.\n"
            "Veja dados/brutos/README.md."
        )
    return achados[0]


F_LEITURAS = localizar("*PLANILHA*GERAL*OVT*.xlsx")
F_GEO = localizar("*eorreferenciamento*OVT*.xlsx")
F_EDL = localizar("*TOTAL*EDL*POR*DS*.xlsx")
LIM_LAT = (-8.30, -7.90)
LIM_LON = (-35.05, -34.80)
GRAU_LAT, GRAU_LON = 8, 34

DMS = re.compile(
    r"(\d{1,3})\s*[º°]\s*(\d{1,2})\s*'\s*([\d.]+)\s*(?:''|\")?\s*([NSEWLO])?"
)
ROMANO = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI", 7: "VII", 8: "VIII"}


def chave_ovt(valor):
    """Normaliza o identificador da armadilha. REC 1001 e REC1001 sao o mesmo."""
    return re.sub(r"\s+", "", str(valor)).upper().strip()


def normaliza_coord(valor, alvo):
    """Converte qualquer um dos cinco formatos encontrados para grau decimal."""
    if valor is None or (isinstance(valor, float) and pd.isna(valor)):
        return None
    txt = str(valor).strip()
    if not txt or txt.lower() == "nan":
        return None

    achou = DMS.search(txt)
    if achou:
        grau, minuto, segundo, _ = achou.groups()
        return int(grau) + int(minuto) / 60 + float(segundo) / 3600

    # O espaco aparece como separador decimal ("8 0803258") e tambem depois
    # do ponto ("8. 0194858"). Remover todo espaco resolve os dois casos.
    try:
        num = float(re.sub(r"\s+", "", txt).replace(",", "."))
    except ValueError:
        return None

    if abs(abs(num) - alvo) < 1:
        return num

    digitos = str(abs(int(num)))
    for corte in (1, 2, 3):
        if corte >= len(digitos):
            break
        cand = float(f"{digitos[:corte]}.{digitos[corte:]}")
        if abs(cand - alvo) < 1:
            return cand
    return None


def sul_oeste(valor):
    """Recife esta inteiro no quadrante sul-oeste; o sinal gravado nao e confiavel."""
    return None if valor is None else -abs(valor)


def no_recife(lat, lon):
    return (
        lat is not None
        and lon is not None
        and LIM_LAT[0] <= lat <= LIM_LAT[1]
        and LIM_LON[0] <= lon <= LIM_LON[1]
    )


def carrega_leituras():
    tab = pd.read_excel(F_LEITURAS, sheet_name="CICLO 1")
    col_obs = next(c for c in tab.columns if str(c).startswith("OBS"))
    tab = tab.rename(columns={col_obs: "OBS"})
    tab["id_ovt"] = tab.ID_OVT.map(chave_ovt)
    tab["n_ovos"] = pd.to_numeric(tab.N_OVOS, errors="coerce")
    tab["obs"] = tab.OBS.astype(str).str.strip().str.upper().replace("NAN", None)
    for col in ("DT_COLETA", "DT_LEITURA", "DT_DIG", "DT_ENVIO_DS"):
        tab[col] = pd.to_datetime(tab[col], errors="coerce")
    tab["dias_coleta_dig"] = (tab.DT_DIG - tab.DT_COLETA).dt.days
    return tab[
        [
            "Ano", "CICLOS", "DS", "BAIRRO", "BAIRRO_AREA", "id_ovt",
            "n_ovos", "obs", "DT_COLETA", "DT_LEITURA", "DT_DIG",
            "DT_ENVIO_DS", "dias_coleta_dig",
        ]
    ].rename(columns={"Ano": "ano", "CICLOS": "ciclo", "DS": "ds",
                      "BAIRRO": "bairro", "BAIRRO_AREA": "bairro_area"})


def carrega_geo():
    xls = pd.ExcelFile(F_GEO)
    blocos = []
    for aba in xls.sheet_names:
        bruto = pd.read_excel(F_GEO, sheet_name=aba, header=None)
        linha_hdr = next(
            (
                i
                for i in range(min(12, len(bruto)))
                if "ID OVT" in " ".join(str(v).upper() for v in bruto.iloc[i])
                and "LATITUDE" in " ".join(str(v).upper() for v in bruto.iloc[i])
            ),
            None,
        )
        if linha_hdr is None:
            continue
        tab = pd.read_excel(F_GEO, sheet_name=aba, header=linha_hdr)
        tab.columns = [str(c).strip().upper() for c in tab.columns]
        tab = tab[tab["ID OVT"].notna()]
        tab["id_ovt"] = tab["ID OVT"].map(chave_ovt)
        # As abas usam os mesmos formatos sujos do cadastro de EDL.
        tab["lat"] = tab.LATITUDE.map(
            lambda v: sul_oeste(normaliza_coord(v, GRAU_LAT))
        )
        tab["lon"] = tab.LONGITUDE.map(
            lambda v: sul_oeste(normaliza_coord(v, GRAU_LON))
        )
        blocos.append(tab[["id_ovt", "lat", "lon"]])
    geo = pd.concat(blocos, ignore_index=True).drop_duplicates("id_ovt")
    geo.loc[~geo.apply(lambda r: no_recife(r.lat, r.lon), axis=1), ["lat", "lon"]] = None
    return geo


def carrega_edl():
    xls = pd.ExcelFile(F_EDL)
    linhas = []
    for num in range(1, 9):
        aba = next(
            (s for s in xls.sheet_names if s.strip() == f"DS {num} - TOTAL"), None
        )
        if aba is None:
            continue
        tab = pd.read_excel(F_EDL, sheet_name=aba, header=4).dropna(how="all")
        tab = tab[tab.iloc[:, 0].notna()]
        col_coord = next(c for c in tab.columns if "COORDENADA" in str(c).upper())
        pos = tab.columns.get_loc(col_coord)
        col_edl = next((c for c in tab.columns if "EDL REAL" in str(c).upper()), None)
        col_bairro = next((c for c in tab.columns if "BAIRRO" in str(c).upper()), None)
        col_tipo = next((c for c in tab.columns if "TIPO PE" in str(c).upper()), None)
        col_nome = next((c for c in tab.columns if "FANTASIA" in str(c).upper()), None)

        for _, reg in tab.iterrows():
            bruto_a, bruto_b = reg.iloc[pos], (
                reg.iloc[pos + 1] if pos + 1 < len(reg) else None
            )
            texto = str(bruto_a).strip()
            if "," in texto and re.search(r"-?\d+\.\d+\s*,\s*-?\d+\.\d+", texto):
                parte_a, parte_b = re.split(r"\s*,\s*", texto, maxsplit=1)
                lat = sul_oeste(normaliza_coord(parte_a, GRAU_LAT))
                lon = sul_oeste(normaliza_coord(parte_b, GRAU_LON))
            else:
                lat = sul_oeste(normaliza_coord(bruto_a, GRAU_LAT))
                lon = sul_oeste(normaliza_coord(bruto_b, GRAU_LON))
            if not no_recife(lat, lon):
                lat = lon = None
            linhas.append(
                {
                    "ds": ROMANO[num],
                    "bairro": reg[col_bairro] if col_bairro else None,
                    "tipo_pe": reg[col_tipo] if col_tipo else None,
                    "nome_pe": reg[col_nome] if col_nome else None,
                    "lat": lat,
                    "lon": lon,
                    "qt_edl": pd.to_numeric(reg[col_edl], errors="coerce")
                    if col_edl
                    else None,
                }
            )
    return pd.DataFrame(linhas)


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)

    leituras = carrega_leituras()
    geo = carrega_geo()
    edl = carrega_edl()

    antes = len(leituras)
    leituras = leituras.merge(geo, on="id_ovt", how="left")
    casadas = leituras.lat.notna().sum()

    print(f"leituras            {antes:6d}")
    print(f"  com coordenada    {casadas:6d}  ({100*casadas/antes:.1f}%)")
    print(f"armadilhas unicas   {leituras.id_ovt.nunique():6d}")
    print(f"  georreferenciadas {geo.lat.notna().sum():6d}")
    print()
    print(f"pontos estrategicos {len(edl):6d}")
    print(f"  com coordenada    {edl.lat.notna().sum():6d}")
    print(f"EDLs totais         {int(edl.qt_edl.sum()):6d}")
    print(f"  georreferenciadas {int(edl.loc[edl.lat.notna(),'qt_edl'].sum()):6d}")

    leituras.to_csv(SAIDA / "leituras.csv", index=False)
    edl.to_csv(SAIDA / "pontos_edl.csv", index=False)


if __name__ == "__main__":
    main()
