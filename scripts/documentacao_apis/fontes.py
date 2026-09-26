from dataclasses import dataclass, field
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
PASTA_SKILLS = RAIZ / ".claude" / "skills"
PASTA_BRUTOS = RAIZ / "dados" / "brutos" / "documentacao"


@dataclass(frozen=True)
class Fonte:
    nome: str
    url_indice: str
    pasta_referencia: Path
    # trechos de caminho que o projeto consome; mudanca neles sai em destaque
    caminhos_usados: tuple = field(default_factory=tuple)


FONTES = {
    "sienge": Fonte(
        nome="sienge",
        url_indice="https://api.sienge.com.br/docs/",
        pasta_referencia=PASTA_SKILLS / "api-sienge" / "referencia",
        caminhos_usados=(
            "/companies", "/cost-centers", "/enterprises", "/units", "/customers",
            "/sales-contracts", "/accounts-statements", "/accounts-balances", "/indexers",
            "/income", "/outcome", "/sales", "/bank-movement", "/defaulters-receivable-bills",
            "/customer-extract-history", "/building-cost-estimation-items", "/auth/token",
        ),
    ),
    "cvcrm": Fonte(
        nome="cvcrm",
        url_indice="https://desenvolvedor.cvcrm.com.br/",
        pasta_referencia=PASTA_SKILLS / "api-cvcrm" / "referencia",
    ),
}
