"""
Authentication middleware for API Key validation.

Validates API keys against app_clients table for secure access.
"""

from typing import Optional

from fastapi import Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from liteads.common.database import get_session
from liteads.common.logger import get_logger
from liteads.models import Status

logger = get_logger(__name__)


class AppClient:
    """Authenticated app client model."""

    def __init__(
        self,
        id: int,
        app_id: str,
        name: str,
        company: Optional[str] = None,
        allowed_slots: Optional[list[str]] = None,
        allowed_ips: Optional[list[str]] = None,
        rate_limit_per_minute: int = 1000,
    ):
        self.id = id
        self.app_id = app_id
        self.name = name
        self.company = company
        self.allowed_slots = allowed_slots or []
        self.allowed_ips = allowed_ips or []
        self.rate_limit_per_minute = rate_limit_per_minute


async def verify_api_key(
    request: Request,
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
) -> Optional[AppClient]:
    """
    Verify API key and return app client if valid.
    
    Returns None if no API key provided (for backwards compatibility).
    Raises HTTPException if API key is invalid.
    """
    # If no API key provided, allow access (backwards compatibility)
    # Remove this check if you want to enforce authentication
    if not x_api_key:
        logger.debug("No API key provided, allowing access")
        return None

    # Get database session
    async for session in get_session():
        try:
            # Query for app client with this API key
            from liteads.models.ad import AppClient as AppClientModel

            stmt = (
                select(AppClientModel)
                .where(AppClientModel.api_key == x_api_key)
                .where(AppClientModel.status == Status.ACTIVE)
            )

            result = await session.execute(stmt)
            app_client_model = result.scalar_one_or_none()

            if not app_client_model:
                logger.warning(
                    "Invalid API key attempted",
                    api_key_prefix=x_api_key[:10] if x_api_key else "None",
                    client_ip=request.client.host if request.client else "unknown",
                )
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid API key",
                    headers={"WWW-Authenticate": "ApiKey"},
                )

            # Validate IP if configured
            client_ip = request.client.host if request.client else None
            if app_client_model.allowed_ips and client_ip:
                # TODO: Implement IP range checking (CIDR)
                # For now, just log
                logger.debug(
                    "IP validation not implemented",
                    client_ip=client_ip,
                    allowed_ips=app_client_model.allowed_ips,
                )

            logger.info(
                "API key validated",
                app_id=app_client_model.app_id,
                app_name=app_client_model.name,
                client_ip=client_ip,
            )

            return AppClient(
                id=app_client_model.id,
                app_id=app_client_model.app_id,
                name=app_client_model.name,
                company=app_client_model.company,
                allowed_slots=app_client_model.allowed_slots or [],
                allowed_ips=app_client_model.allowed_ips or [],
                rate_limit_per_minute=app_client_model.rate_limit_per_minute or 1000,
            )

        finally:
            await session.close()

    return None


def require_api_key(
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
) -> str:
    """
    Dependency that requires API key to be present.
    
    Use this for endpoints that MUST have authentication.
    """
    if not x_api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="API key required",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    return x_api_key
