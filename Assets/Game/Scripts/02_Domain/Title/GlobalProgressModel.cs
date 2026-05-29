using System;

public class GlobalProgressModel
{
    private GlobalProgressDTO m_progressDTO;

    public GlobalProgressModel(GlobalProgressDTO progressDTO)
    {
        m_progressDTO = progressDTO;
    }

    public GlobalProgressDTO ProgressDTO
    {
        get
        {
            return m_progressDTO;
        }
    }

    public string GetFormattedPlayTime()
    {
        if (m_progressDTO == null)
        {
            return "0h 00m";
        }
        int totalMinutes = (int)(m_progressDTO.AccumulatedTime / 60f);
        int hours = totalMinutes / 60;
        int minutes = totalMinutes % 60;
        return string.Format("{0}h {1:00}m", hours, minutes);
    }
}
