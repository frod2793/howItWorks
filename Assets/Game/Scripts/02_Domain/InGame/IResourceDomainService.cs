using System;

namespace Domain.InGame
{
    public interface IResourceDomainService
    {
        event Action<SidePanelDTO> OnResourceChanged;
        SidePanelDTO CurrentResources { get; }
        void ConsumeCato();
        void RejectCato();
        void ApplyEmotionDelta(int sadness, int joy, int curiosity, int fear, int confusion);
        void ApplyOuterTrustDelta(int amount);
        void ApplyMonitoringDelta(int amount);
        void IncreaseLoopAwareness();
        void SetInitialData(SidePanelDTO data);
        void ApplyCatoDelta(int amount);
    }
}
