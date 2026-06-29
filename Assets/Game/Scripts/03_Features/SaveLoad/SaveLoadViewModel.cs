using System;
using System.Collections.Generic;
using Domain.InGame;
using UnityEngine;

public class SaveLoadViewModel : ISaveLoadViewModel
{
    private readonly SaveLoadModel m_model;
    private readonly List<SaveDataFileDTO> m_slots = new List<SaveDataFileDTO>();
    private int m_selectedIndex = 0;
    private GlobalProgressDataDTO m_globalProgress;
    private bool m_isSaveAllowed;

    public IReadOnlyList<SaveDataFileDTO> SlotList
    {
        get
        {
            return m_slots;
        }
    }

    public int SelectedSlotIndex
    {
        get
        {
            return m_selectedIndex;
        }
    }

    public GlobalProgressDataDTO GlobalProgress
    {
        get
        {
            return m_globalProgress;
        }
    }

    public bool IsSaveActionAllowed
    {
        get
        {
            return m_isSaveAllowed;
        }
    }

    public event Action OnStateChanged;
    public event Action OnCloseRequested;

    public SaveLoadViewModel(SaveLoadModel model)
    {
        m_model = model;
    }

    public void InitializeViewModel(bool isSaveAllowed)
    {
        m_isSaveAllowed = isSaveAllowed;
        m_slots.Clear();
        for (int i = 0; i < 5; i++)
        {
            var data = m_model.LoadSlotData(i);
            if (data == null)
            {
                var emptyData = new SaveDataFileDTO();
                emptyData.slotId = i;
                emptyData.savedAt = string.Empty;
                m_slots.Add(emptyData);
            }
            else
            {
                m_slots.Add(data);
            }
        }
        m_globalProgress = m_model.GetGlobalProgress();
        m_selectedIndex = 0;
        
        if (OnStateChanged != null)
        {
            OnStateChanged.Invoke();
        }
    }

    public void SelectSlot(int index)
    {
        if (index < 0 || index >= m_slots.Count)
        {
            return;
        }
        m_selectedIndex = index;
        if (OnStateChanged != null)
        {
            OnStateChanged.Invoke();
        }
    }

    public void ExecuteLoad()
    {
        var targetSlot = m_slots[m_selectedIndex];
        if (string.IsNullOrEmpty(targetSlot.savedAt))
        {
            Debug.LogWarning("[SaveLoadViewModel] 비어 있는 슬롯은 로드할 수 없습니다.");
            return;
        }
        Debug.Log(string.Format("[SaveLoadViewModel] {0}번 슬롯 데이터 로드 실행", m_selectedIndex));
    }

    public void ExecuteSave(SaveDataFileDTO currentData)
    {
        if (m_isSaveAllowed == false)
        {
            Debug.LogWarning("[SaveLoadViewModel] 로비 상태에서는 저장이 불가능합니다.");
            return;
        }
        if (currentData == null)
        {
            return;
        }
        currentData.slotId = m_selectedIndex;
        currentData.savedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        m_model.SaveSlotData(currentData);
        m_slots[m_selectedIndex] = currentData;
        Debug.Log(string.Format("[SaveLoadViewModel] {0}번 슬롯 데이터 저장 완료", m_selectedIndex));

        if (OnStateChanged != null)
        {
            OnStateChanged.Invoke();
        }
    }

    public void ExecuteDelete()
    {
        m_model.DeleteSlotData(m_selectedIndex);
        var emptyData = new SaveDataFileDTO();
        emptyData.slotId = m_selectedIndex;
        emptyData.savedAt = string.Empty;
        m_slots[m_selectedIndex] = emptyData;
        Debug.Log(string.Format("[SaveLoadViewModel] {0}번 슬롯 데이터 삭제 완료", m_selectedIndex));

        if (OnStateChanged != null)
        {
            OnStateChanged.Invoke();
        }
    }

    public void Close()
    {
        if (OnCloseRequested != null)
        {
            OnCloseRequested.Invoke();
        }
    }
}
