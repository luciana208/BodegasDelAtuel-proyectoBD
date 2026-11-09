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


class Permiso(BaseModel):
    cod_permiso: str
    fecha_emision: date
    fecha_vencimiento: date


class ClienteEntrada(BaseModel):
    nombre: str
    tipo_documento: str = Field(description='DNI, CUIT o PAS')
    nro_documento: str
    direccion: str
    id_localidad: int
    tipo: str = Field(description='socio, distribuidor o exportador')
    nro_carnet: int | None = Field(default=None, description='solo socios')
    zona_cobertura: str | None = Field(default=None, description='solo distribuidores')
    nro_habilitacion: str | None = Field(default=None, description='solo distribuidores')
    pais_destino: str | None = Field(default=None, description='solo exportadores')
    permisos: list[Permiso] = Field(default=[], description='solo exportadores')
