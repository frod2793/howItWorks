using System;

[Serializable]
public class GlobalProgressDTO
{
    private int m_playCount;
    private float m_accumulatedTime;
    private int m_unlockedEndings;
    private int m_totalEndings;
    private int m_archiveCount;
    private int m_totalArchives;
    private int m_subplotCount;
    private int m_totalSubplots;

    public int PlayCount
    {
        get
        {
            return m_playCount;
        }
        set
        {
            m_playCount = value;
        }
    }

    public float AccumulatedTime
    {
        get
        {
            return m_accumulatedTime;
        }
        set
        {
            m_accumulatedTime = value;
        }
    }

    public int UnlockedEndings
    {
        get
        {
            return m_unlockedEndings;
        }
        set
        {
            m_unlockedEndings = value;
        }
    }

    public int TotalEndings
    {
        get
        {
            return m_totalEndings;
        }
        set
        {
            m_totalEndings = value;
        }
    }

    public int ArchiveCount
    {
        get
        {
            return m_archiveCount;
        }
        set
        {
            m_archiveCount = value;
        }
    }

    public int TotalArchives
    {
        get
        {
            return m_totalArchives;
        }
        set
        {
            m_totalArchives = value;
        }
    }

    public int SubplotCount
    {
        get
        {
            return m_subplotCount;
        }
        set
        {
            m_subplotCount = value;
        }
    }

    public int TotalSubplots
    {
        get
        {
            return m_totalSubplots;
        }
        set
        {
            m_totalSubplots = value;
        }
    }
}
