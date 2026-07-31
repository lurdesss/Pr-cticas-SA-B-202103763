"""Modelos ORM (tabla física en PostgreSQL).

El modelo ORM se mantiene separado de la entidad de dominio a propósito:
si mañana cambia el motor de base de datos, la entidad no se toca.
"""

import uuid
from decimal import Decimal

from sqlalchemy import CheckConstraint, Numeric, SmallInteger, String
from sqlalchemy.dialects import postgresql
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.domain.entities import EstadoSolicitud

ESTADOS_PERMITIDOS = ", ".join(f"'{estado.value}'" for estado in EstadoSolicitud)


class SolicitudOperativaModel(Base):
    """Representación en base de datos de una solicitud operativa."""

    __tablename__ = "solicitudes_operativas"
    __table_args__ = (
        CheckConstraint("prioridad BETWEEN 1 AND 5", name="ck_prioridad_rango"),
        CheckConstraint("costo_estimado >= 0", name="ck_costo_no_negativo"),
        CheckConstraint(f"estado IN ({ESTADOS_PERMITIDOS})", name="ck_estado_valido"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        postgresql.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    titulo: Mapped[str] = mapped_column(String(120), nullable=False)
    area_solicitante: Mapped[str] = mapped_column(String(80), nullable=False)
    prioridad: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    costo_estimado: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    estado: Mapped[str] = mapped_column(String(20), nullable=False)
