using System;
using System.IO;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using Cysharp.Threading.Tasks;
using Domain.InGame;
using UnityEngine.InputSystem;
using VContainer;

public class SaveLoadView : MonoBehaviour, IStackablePopup
{
    [SerializeField] private RectTransform m_contentContainer;
    [SerializeField] private GameObject m_slotItemPrefab;
    [SerializeField] private Image m_thumbnailImage;
    [SerializeField] private TextMeshProUGUI m_metaText;
    [SerializeField] private TextMeshProUGUI m_detailText;
    [SerializeField] private Button m_loadButton;
    [SerializeField] private Button m_saveButton;
    [SerializeField] private Button m_deleteButton;
    [SerializeField] private TextMeshProUGUI m_globalProgressText;

    private IUIStackService m_uiStackService;
    private ISaveLoadViewModel m_viewModel;
    private bool m_isOpened = false;
    private Sprite m_loadedSprite;

    [Inject]
    public void Construct(IUIStackService uiStackService)
    {
        m_uiStackService = uiStackService;
    }

    public void Initialize(ISaveLoadViewModel viewModel)
    {
        m_viewModel = viewModel;
        if (m_viewModel != null)
        {
            m_viewModel.OnStateChanged += RefreshUI;
        }
    }

    public void func_Open(bool isSaveAllowed)
    {
        m_isOpened = true;
        if (m_uiStackService != null)
        {
            m_uiStackService.Push(this);
        }
        gameObject.SetActive(true);
        if (m_viewModel != null)
        {
            m_viewModel.InitializeViewModel(isSaveAllowed);
        }
    }

    public void func_Close()
    {
        m_isOpened = false;
        if (m_uiStackService != null)
        {
            m_uiStackService.Pop(this);
        }
        CleanUpResources();
        gameObject.SetActive(false);
        if (m_viewModel != null)
        {
            m_viewModel.Close();
        }
    }

    private void Update()
    {
        if (m_isOpened == false || m_viewModel == null)
        {
            return;
        }

        var keyboard = Keyboard.current;
        if (keyboard == null)
        {
            return;
        }

        // UIStackService가 통합 제어하므로 ESC 체크는 삭제함

        if (keyboard.upArrowKey.wasPressedThisFrame || keyboard.wKey.wasPressedThisFrame)
        {
            m_viewModel.SelectSlot((m_viewModel.SelectedSlotIndex - 1 + m_viewModel.SlotList.Count) % m_viewModel.SlotList.Count);
        }
        else if (keyboard.downArrowKey.wasPressedThisFrame || keyboard.sKey.wasPressedThisFrame)
        {
            m_viewModel.SelectSlot((m_viewModel.SelectedSlotIndex + 1) % m_viewModel.SlotList.Count);
        }
        else if (keyboard.enterKey.wasPressedThisFrame || keyboard.spaceKey.wasPressedThisFrame)
        {
            func_OnLoadButtonClick();
        }
        else if (keyboard.deleteKey.wasPressedThisFrame || keyboard.backspaceKey.wasPressedThisFrame)
        {
            func_OnDeleteButtonClick();
        }
        else if (keyboard.ctrlKey.isPressed && keyboard.sKey.wasPressedThisFrame)
        {
            func_OnSaveButtonClick();
        }
    }

    private void RefreshUI()
    {
        if (m_viewModel == null)
        {
            return;
        }

        int selectedIdx = m_viewModel.SelectedSlotIndex;
        var targetSlot = m_viewModel.SlotList[selectedIdx];

        RefreshSlotListVisuals();
        RefreshSlotDetail(targetSlot);
        RefreshGlobalProgress();

        if (m_loadButton != null)
        {
            m_loadButton.interactable = string.IsNullOrEmpty(targetSlot.savedAt) == false;
        }
        if (m_saveButton != null)
        {
            m_saveButton.interactable = m_viewModel.IsSaveActionAllowed;
        }
        if (m_deleteButton != null)
        {
            m_deleteButton.interactable = string.IsNullOrEmpty(targetSlot.savedAt) == false;
        }
    }

    private void RefreshSlotListVisuals()
    {
        if (m_contentContainer == null)
        {
            return;
        }
        int childCount = m_contentContainer.childCount;
        for (int i = 0; i < childCount; i++)
        {
            Transform child = m_contentContainer.GetChild(i);
            var txt = child.GetComponentInChildren<TextMeshProUGUI>();
            if (txt != null)
            {
                if (i == m_viewModel.SelectedSlotIndex)
                {
                    txt.color = new Color(0.75f, 0.22f, 0.17f, 1.0f);
                }
                else
                {
                    txt.color = new Color(0.05f, 0.05f, 0.06f, 1.0f);
                }
            }
        }
    }

    private void RefreshSlotDetail(SaveDataFileDTO slot)
    {
        CleanUpResources();

        if (string.IsNullOrEmpty(slot.savedAt))
        {
            if (m_metaText != null)
            {
                m_metaText.text = "비어 있는 슬롯";
            }
            if (m_detailText != null)
            {
                m_detailText.text = "저장된 데이터가 없습니다.";
            }
            if (m_thumbnailImage != null)
            {
                m_thumbnailImage.sprite = null;
            }
            return;
        }

        if (m_metaText != null)
        {
            int playthroughCount = 0;
            if (slot.globalProgress != null)
            {
                playthroughCount = slot.globalProgress.playthroughCount;
            }
            m_metaText.text = string.Format("슬롯 {0} — 회차 {1} / {2} / {3}", slot.slotId + 1, playthroughCount, "수동", slot.savedAt);
        }

        if (m_detailText != null)
        {
            m_detailText.text = string.Format("씬 ID: {0}\n카마: {1} | 감정: {2} | 감시도: {3} | 신뢰도: {4}", 
                slot.currentSceneId, 
                slot.resources.karma, 
                slot.resources.emotion, 
                slot.resources.monitoring, 
                slot.resources.trust);
        }

        LoadThumbnailAsync(slot.slotId).Forget();
    }

    private async UniTaskVoid LoadThumbnailAsync(int slotId)
    {
        string path = Path.Combine(Application.persistentDataPath, "Saves", string.Format("save_slot_{0}.png", slotId));
        if (File.Exists(path) == false)
        {
            if (m_thumbnailImage != null)
            {
                m_thumbnailImage.sprite = null;
            }
            return;
        }

        byte[] bytes = await File.ReadAllBytesAsync(path);
        var tex = new Texture2D(2, 2);
        tex.LoadImage(bytes);

        m_loadedSprite = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f));
        if (m_thumbnailImage != null)
        {
            m_thumbnailImage.sprite = m_loadedSprite;
        }
    }

    private void RefreshGlobalProgress()
    {
        if (m_globalProgressText == null || m_viewModel.GlobalProgress == null)
        {
            return;
        }

        var progress = m_viewModel.GlobalProgress;
        int unlockedEndings = progress.unlockedEndings != null ? progress.unlockedEndings.Count : 0;
        m_globalProgressText.text = string.Format("엔딩 {0}/9 · 도전과제 {1}/24 · 도감 {2}/19 · 서브플롯 {3}/5", 
            unlockedEndings, 
            0, 
            progress.archiveCount, 
            progress.playthroughCount);
    }

    public void func_OnLoadButtonClick()
    {
        if (m_viewModel != null)
        {
            m_viewModel.ExecuteLoad();
        }
    }

    public void func_OnSaveButtonClick()
    {
        if (m_viewModel == null)
        {
            return;
        }
        
        CaptureAndSaveAsync().Forget();
    }

    private async UniTaskVoid CaptureAndSaveAsync()
    {
        await UniTask.WaitForEndOfFrame(this);
        
        int width = Screen.width;
        int height = Screen.height;
        var screenTex = new Texture2D(width, height, TextureFormat.RGB24, false);
        screenTex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
        screenTex.Apply();

        int targetWidth = 320;
        int targetHeight = 180;
        var rt = RenderTexture.GetTemporary(targetWidth, targetHeight, 0, RenderTextureFormat.Default);
        RenderTexture.active = rt;
        Graphics.Blit(screenTex, rt);
        
        var resultTex = new Texture2D(targetWidth, targetHeight, TextureFormat.RGB24, false);
        resultTex.ReadPixels(new Rect(0, 0, targetWidth, targetHeight), 0, 0);
        resultTex.Apply();

        RenderTexture.active = null;
        RenderTexture.ReleaseTemporary(rt);
        
        if (screenTex != null)
        {
            UnityEngine.Object.Destroy(screenTex);
        }

        byte[] bytes = resultTex.EncodeToPNG();
        if (resultTex != null)
        {
            UnityEngine.Object.Destroy(resultTex);
        }

        string saveDir = Path.Combine(Application.persistentDataPath, "Saves");
        if (Directory.Exists(saveDir) == false)
        {
            Directory.CreateDirectory(saveDir);
        }
        string path = Path.Combine(saveDir, string.Format("save_slot_{0}.png", m_viewModel.SelectedSlotIndex));
        await File.WriteAllBytesAsync(path, bytes);

        var dummyData = new SaveDataFileDTO();
        dummyData.currentSceneId = "InGame";
        dummyData.globalProgress = m_viewModel.GlobalProgress;
        dummyData.resources = new ResourceDataDTO { karma = 10, emotion = 5, monitoring = 20, trust = 80 };
        m_viewModel.ExecuteSave(dummyData);
    }

    public void func_OnDeleteButtonClick()
    {
        if (m_viewModel != null)
        {
            m_viewModel.ExecuteDelete();
        }
    }

    private void CleanUpResources()
    {
        if (m_loadedSprite != null)
        {
            if (m_loadedSprite.texture != null)
            {
                UnityEngine.Object.Destroy(m_loadedSprite.texture);
            }
            UnityEngine.Object.Destroy(m_loadedSprite);
            m_loadedSprite = null;
        }
    }

    private void OnDestroy()
    {
        CleanUpResources();
        if (m_viewModel != null)
        {
            m_viewModel.OnStateChanged -= RefreshUI;
        }
    }
    public void ClosePopup()
    {
        func_Close();
    }

    public bool IsPopupActive()
    {
        return m_isOpened;
    }
}
