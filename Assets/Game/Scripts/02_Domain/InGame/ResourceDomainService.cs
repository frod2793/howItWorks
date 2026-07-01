using System;

namespace Domain.InGame
{
    public class ResourceDomainService : IResourceDomainService
    {
        public event Action<SidePanelDTO> OnResourceChanged;

        private SidePanelDTO m_currentResources;

        public SidePanelDTO CurrentResources
        {
            get
            {
                return m_currentResources;
            }
        }

        public ResourceDomainService()
        {
            m_currentResources = new SidePanelDTO
            {
                CatoStocks = 2,
                MaxCatoStocks = 5,
                Sadness = 6,
                Joy = 1,
                Curiosity = 7,
                Fear = 3,
                Confusion = 3,
                Monitoring = 5,
                Trust = 4,
                LoopAwareness = 1,
                MaxLoopAwareness = 5,
                ActBranchInfo = "D1 · R · V · β",
                PassedScenesInfo = "씬 2 · 3 · 5 · 7"
            };
        }

        public void SetInitialData(SidePanelDTO data)
        {
            if (data != null)
            {
                m_currentResources = data;
                EvaluateLonging();
                NotifyChanged();
            }
        }

        public void ConsumeCato()
        {
            if (m_currentResources.CatoStocks > 0)
            {
                m_currentResources.CatoStocks = Math.Max(0, m_currentResources.CatoStocks - 1);
                m_currentResources.Monitoring = Math.Max(0, m_currentResources.Monitoring - 1);
                
                m_currentResources.Sadness = Math.Max(0, m_currentResources.Sadness - 2);
                m_currentResources.Joy = Math.Max(0, m_currentResources.Joy - 2);
                m_currentResources.Curiosity = Math.Max(0, m_currentResources.Curiosity - 2);
                m_currentResources.Fear = Math.Max(0, m_currentResources.Fear - 2);
                m_currentResources.Confusion = Math.Max(0, m_currentResources.Confusion - 2);

                EvaluateLonging();
                NotifyChanged();
            }
        }

        public void RejectCato()
        {
            m_currentResources.Monitoring = Math.Min(10, m_currentResources.Monitoring + 1);
            
            m_currentResources.Sadness = Math.Min(10, m_currentResources.Sadness + 1);
            m_currentResources.Joy = Math.Min(10, m_currentResources.Joy + 1);
            m_currentResources.Curiosity = Math.Min(10, m_currentResources.Curiosity + 1);
            m_currentResources.Fear = Math.Min(10, m_currentResources.Fear + 1);
            m_currentResources.Confusion = Math.Min(10, m_currentResources.Confusion + 1);

            m_currentResources.LoopAwareness = Math.Min(5, m_currentResources.LoopAwareness + 1);

            EvaluateLonging();
            NotifyChanged();
        }

        public void ApplyEmotionDelta(int sadness, int joy, int curiosity, int fear, int confusion)
        {
            m_currentResources.Sadness = Math.Max(0, Math.Min(10, m_currentResources.Sadness + sadness));
            m_currentResources.Joy = Math.Max(0, Math.Min(10, m_currentResources.Joy + joy));
            m_currentResources.Curiosity = Math.Max(0, Math.Min(10, m_currentResources.Curiosity + curiosity));
            m_currentResources.Fear = Math.Max(0, Math.Min(10, m_currentResources.Fear + fear));
            m_currentResources.Confusion = Math.Max(0, Math.Min(10, m_currentResources.Confusion + confusion));

            EvaluateLonging();
            NotifyChanged();
        }

        public void ApplyOuterTrustDelta(int amount)
        {
            m_currentResources.Trust = Math.Max(0, Math.Min(10, m_currentResources.Trust + amount));
            NotifyChanged();
        }

        public void ApplyMonitoringDelta(int amount)
        {
            m_currentResources.Monitoring = Math.Max(0, Math.Min(10, m_currentResources.Monitoring + amount));
            NotifyChanged();
        }

        public void IncreaseLoopAwareness()
        {
            m_currentResources.LoopAwareness = Math.Max(0, Math.Min(5, m_currentResources.LoopAwareness + 1));
            NotifyChanged();
        }

        public void ApplyCatoDelta(int amount)
        {
            m_currentResources.CatoStocks = Math.Max(0, Math.Min(m_currentResources.MaxCatoStocks, m_currentResources.CatoStocks + amount));
            NotifyChanged();
        }

        private void EvaluateLonging()
        {
            m_currentResources.IsLongingActive = (m_currentResources.Sadness >= 3 && m_currentResources.Joy >= 3);
        }

        private void NotifyChanged()
        {
            if (OnResourceChanged != null)
            {
                OnResourceChanged.Invoke(m_currentResources);
            }
        }
    }
}
