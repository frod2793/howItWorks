using System;

public class GlobalProgressViewModel
{
    private readonly GlobalProgressModel m_model;

    public event Action OnStateChanged;

    public GlobalProgressViewModel(GlobalProgressModel model)
    {
        m_model = model;
    }

    public string HeaderText
    {
        get
        {
            return "GLOBAL PROGRESS";
        }
    }

    public string PlayTimeText
    {
        get
        {
            if (m_model == null)
            {
                return "회차 1 · 누적 0h 00m";
            }
            int playCount = m_model.ProgressDTO != null ? m_model.ProgressDTO.PlayCount : 1;
            return string.Format("회차 {0} · 누적 {1}", playCount, m_model.GetFormattedPlayTime());
        }
    }

    public string EndingText
    {
        get
        {
            if (m_model == null || m_model.ProgressDTO == null)
            {
                return "엔딩: 0 / 0";
            }
            return string.Format("엔딩: {0} / {1}", m_model.ProgressDTO.UnlockedEndings, m_model.ProgressDTO.TotalEndings);
        }
    }

    public string SubplotText
    {
        get
        {
            if (m_model == null || m_model.ProgressDTO == null)
            {
                return "도감: 0 / 0 · 서브플롯: 0 / 0";
            }
            return string.Format("도감: {0} / {1} · 서브플롯: {2} / {3}",
                m_model.ProgressDTO.ArchiveCount,
                m_model.ProgressDTO.TotalArchives,
                m_model.ProgressDTO.SubplotCount,
                m_model.ProgressDTO.TotalSubplots);
        }
    }

    public void RefreshState()
    {
        if (OnStateChanged != null)
        {
            OnStateChanged.Invoke();
        }
    }
}
