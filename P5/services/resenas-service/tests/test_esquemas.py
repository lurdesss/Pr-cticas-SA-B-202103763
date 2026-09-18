"""Pruebas de validacion del contrato de entrada de resenas. Son pruebas
de contrato, no de base de datos: confirman que Pydantic rechaza datos
invalidos ANTES de que lleguen a tocar la base de datos.
"""
import pytest
from pydantic import ValidationError

from app.esquemas import ResenaEntrada


def test_acepta_una_resena_valida():
    entrada = ResenaEntrada(producto_id="1", calificacion=5, comentario="Excelente")
    assert entrada.calificacion == 5


def test_rechaza_calificacion_fuera_de_rango():
    with pytest.raises(ValidationError):
        ResenaEntrada(producto_id="1", calificacion=9)


def test_rechaza_calificacion_menor_a_uno():
    with pytest.raises(ValidationError):
        ResenaEntrada(producto_id="1", calificacion=0)


def test_comentario_es_opcional():
    entrada = ResenaEntrada(producto_id="1", calificacion=3)
    assert entrada.comentario == ""


def test_rechaza_producto_id_vacio():
    with pytest.raises(ValidationError):
        ResenaEntrada(producto_id="", calificacion=3)
