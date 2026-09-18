"""Pruebas de la logica pura del inventario. No tocan la base de datos:
_aplicar() es la unica funcion sin efectos secundarios de servicio.py,
y es justamente la que decide como afecta cada tipo de movimiento a la
existencia -- el punto que se corrigio a mano durante el desarrollo del
proyecto (un "ajuste" reemplaza la existencia, no la suma).
"""
from decimal import Decimal

from app.servicio import _aplicar


def test_entrada_suma_a_la_existencia():
    resultado = _aplicar(Decimal("10"), "entrada", Decimal("5"))
    assert resultado == Decimal("15")


def test_salida_resta_de_la_existencia():
    resultado = _aplicar(Decimal("10"), "salida", Decimal("4"))
    assert resultado == Decimal("6")


def test_ajuste_reemplaza_la_existencia_no_la_suma():
    # Un ajuste es el resultado de un conteo fisico: la cantidad ES la
    # existencia real, no un incremento. Ver el comentario en servicio.py.
    resultado = _aplicar(Decimal("10"), "ajuste", Decimal("3"))
    assert resultado == Decimal("3")
