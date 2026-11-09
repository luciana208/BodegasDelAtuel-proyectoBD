'''
cuerpos de los pedidos. solo validan el formato (tipos y campos obligatorios);
las reglas de negocio las controla la base
'''
from datetime import date
from decimal import Decimal

from pydantic import BaseModel, Field


class Corte(BaseModel):
    id_cepa: int
    porcentaje: Decimal


class VinoEntrada(BaseModel):
    nombre: str
    tipo: str = Field(description='tinto, blanco, rosado o espumante')
    anada: int
    volumen_ml: int
    graduacion: Decimal
    precio: Decimal
    cuit_bodega: str
    composicion: list[Corte] = Field(description='cepas con su porcentaje de corte')
    maridajes: list[int] = Field(default=[], description='ids de maridaje')
