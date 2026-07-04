using UnityEngine;
using UnityEngine.UI;
using System.Collections.Generic;
using Domain.InGame;
using TMPro;
using VContainer;

/// <summary>
/// [기능]: 기획서 13번 슬라이드 기반의 도감 UI 바인딩 및 키보드 입력을 처리하는 뷰 컴포넌트입니다.
/// [작성자]: 윤승종
/// </summary>
namespace Features.InGame
{
    public class InGameEncyclopediaView : MonoBehaviour, IStackablePopup
    {
        #region UI 참조 (Inspector)
        [SerializeField] private GameObject m_encyclopediaPanel;
        [SerializeField] private RectTransform m_itemGridParent;
        [SerializeField] private GameObject m_encyclopediaCardPrefab;
        [SerializeField] private Button m_closeButton;

        [Header("카테고리 탭")]
        [SerializeField] private Button m_characterTabButton;
        [SerializeField] private Button m_itemTabButton;
        [SerializeField] private Button m_cgTabButton;
        [SerializeField] private Button m_soundTabButton;

        [Header("필터 토글")]
        [SerializeField] private Button m_filterToggleButton;
        [SerializeField] private TextMeshProUGUI m_filterText;

        [Header("상세 설명 팝업 (오버레이)")]
        [SerializeField] private GameObject m_detailPopupOverlay;
        [SerializeField] private Button m_detailCloseButton;
        [SerializeField] private TextMeshProUGUI m_detailNameText;
        [SerializeField] private TextMeshProUGUI m_detailDescriptionText;
        [SerializeField] private Image m_previewImage;
        [SerializeField] private Button m_playButton;
        #endregion

        #region 내부 필드 (Private Fields)
        private IUIStackService m_uiStackService;
        private IInGameEncyclopediaViewModel m_viewModel;
        private List<GameObject> m_spawnedCards = new List<GameObject>();
        #endregion

        #region 초기화 (Initialization)
        /// <summary>
        /// [기능]: DI 컨테이너로부터 필요한 의존성을 주입받습니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        [Inject]
        public void Construct(IUIStackService uiStackService, IInGameEncyclopediaViewModel viewModel)
        {
            m_uiStackService = uiStackService;
            m_viewModel = viewModel;
        }

        /// <summary>
        /// [기능]: 도감 뷰를 초기화하고 뷰모델 상태 이벤트를 바인딩합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        public void Initialize(List<string> unlockedItems)
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDataChanged += RefreshUI;
                m_viewModel.OnDetailOpened += func_OnDetailOpened;
                m_viewModel.OnDetailClosed += func_OnDetailClosed;
                m_viewModel.Initialize(unlockedItems);
            }

            if (m_characterTabButton != null)
            {
                m_characterTabButton.onClick.AddListener(() => m_viewModel?.func_SelectCategory("Character"));
            }
            if (m_itemTabButton != null)
            {
                m_itemTabButton.onClick.AddListener(() => m_viewModel?.func_SelectCategory("Item"));
            }
            if (m_cgTabButton != null)
            {
                m_cgTabButton.onClick.AddListener(() => m_viewModel?.func_SelectCategory("CG"));
            }
            if (m_soundTabButton != null)
            {
                m_soundTabButton.onClick.AddListener(() => m_viewModel?.func_SelectCategory("Sound"));
            }

            if (m_filterToggleButton != null)
            {
                m_filterToggleButton.onClick.AddListener(() => m_viewModel?.func_ToggleFilter());
            }

            if (m_closeButton != null)
            {
                m_closeButton.onClick.AddListener(func_Close);
            }

            if (m_detailCloseButton != null)
            {
                m_detailCloseButton.onClick.AddListener(() => m_viewModel?.func_CloseDetail());
            }

            var canvas = GetComponent<Canvas>();
            if (canvas != null)
            {
                canvas.enabled = false;
            }

            func_OnDetailClosed();
            func_Close();
        }
        #endregion

        #region 공개 메서드 (Public Methods)
        /// <summary>
        /// [기능]: 도감 화면을 활성화하고 스택에 등록합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        public void func_Open()
        {
            if (m_uiStackService != null)
            {
                m_uiStackService.Push(this);
            }
            var canvas = GetComponent<Canvas>();
            if (canvas != null)
            {
                canvas.enabled = true;
            }

            if (m_encyclopediaPanel != null)
            {
                m_encyclopediaPanel.SetActive(true);
            }
            m_viewModel?.func_SelectCategory("Character");
        }

        /// <summary>
        /// [기능]: 도감 화면을 비활성화하고 스택에서 제거합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        public void func_Close()
        {
            if (m_uiStackService != null)
            {
                m_uiStackService.Pop(this);
            }
            var canvas = GetComponent<Canvas>();
            if (canvas != null)
            {
                canvas.enabled = false;
            }

            if (m_encyclopediaPanel != null)
            {
                m_encyclopediaPanel.SetActive(false);
            }
            func_OnDetailClosed();
        }

        /// <summary>
        /// [기능]: IStackablePopup 닫기 인터페이스 구현 메서드입니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        public void ClosePopup()
        {
            func_Close();
        }

        /// <summary>
        /// [기능]: 도감 팝업의 활성 유무 상태를 반환합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        public bool IsPopupActive()
        {
            return m_encyclopediaPanel != null && m_encyclopediaPanel.activeSelf;
        }
        #endregion

        #region 내부 메서드 (Private Methods)
        /// <summary>
        /// [기능]: 뷰모델 상태를 기반으로 UI 전체 데이터를 다시 그립니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        private void RefreshUI()
        {
            if (m_viewModel == null)
            {
                return;
            }

            // 1. 카테고리 탭 수치 갱신
            UpdateTabButtonText(m_characterTabButton, "캐릭터", "Character");
            UpdateTabButtonText(m_itemTabButton, "아이템", "Item");
            UpdateTabButtonText(m_cgTabButton, "CG 갤러리", "CG");
            UpdateTabButtonText(m_soundTabButton, "사운드룸", "Sound");

            // 2. 필터 버튼 텍스트 갱신
            if (m_filterText != null)
            {
                m_filterText.text = m_viewModel.ShowOnlyUnlocked ? "해금만 보기: ON" : "해금만 보기: OFF";
            }

            // 3. 카드 클리어 및 3열 그리드 생성
            if (m_itemGridParent != null)
            {
                for (int i = m_itemGridParent.childCount - 1; i >= 0; i--)
                {
                    var child = m_itemGridParent.GetChild(i).gameObject;
                    if (child != null)
                    {
                        Destroy(child);
                    }
                }
            }
            m_spawnedCards.Clear();

            if (m_encyclopediaCardPrefab == null || m_itemGridParent == null)
            {
                return;
            }

            var items = m_viewModel.CurrentItems;
            for (int i = 0; i < items.Count; i++)
            {
                var item = items[i];
                var inst = Instantiate(m_encyclopediaCardPrefab, m_itemGridParent);
                if (inst != null)
                {
                    inst.SetActive(true);
                    m_spawnedCards.Add(inst);

                    var nameText = inst.transform.Find("NameText")?.GetComponent<TextMeshProUGUI>();
                    var tagText = inst.transform.Find("TagText")?.GetComponent<TextMeshProUGUI>();
                    var iconImage = inst.transform.Find("IconImage")?.GetComponent<Image>();
                    var lockIcon = inst.transform.Find("LockIcon")?.GetComponent<Image>();

                    if (nameText != null)
                    {
                        nameText.text = item.IsUnlocked ? item.Name : "??? (미해금)";
                    }
                    if (tagText != null)
                    {
                        tagText.text = item.IsUnlocked ? item.Tag : "";
                    }

                    if (iconImage != null)
                    {
                        if (item.IsUnlocked)
                        {
                            iconImage.color = Color.white;
                            var sprite = Resources.Load<Sprite>(item.IconPath);
                            if (sprite != null)
                            {
                                iconImage.sprite = sprite;
                            }
                        }
                        else
                        {
                            iconImage.color = new Color(0.2f, 0.2f, 0.2f, 1.0f);
                        }
                    }

                    if (lockIcon != null)
                    {
                        lockIcon.gameObject.SetActive(!item.IsUnlocked);
                    }

                    var cardBg = inst.GetComponent<Image>();
                    if (cardBg != null)
                    {
                        cardBg.color = item.IsUnlocked ? Color.white : new Color(0.9f, 0.9f, 0.88f, 1.0f);
                    }

                    var btn = inst.GetComponent<Button>();
                    if (btn != null)
                    {
                        btn.onClick.AddListener(() => m_viewModel.func_SelectCard(item.Id));
                    }
                }
            }
        }

        /// <summary>
        /// [기능]: 특정 카테고리 버튼의 텍스트에 진행도를 갱신합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        private void UpdateTabButtonText(Button tabButton, string prefix, string category)
        {
            if (tabButton == null)
            {
                return;
            }
            var textComp = tabButton.GetComponentInChildren<TextMeshProUGUI>();
            if (textComp != null && m_viewModel != null)
            {
                var progress = m_viewModel.GetCategoryProgress(category);
                textComp.text = $"{prefix} {progress.unlocked} / {progress.total}";
            }
        }

        /// <summary>
        /// [기능]: 카드가 선택되어 뷰모델에서 상세창 오픈 이벤트 시 처리할 콜백입니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        private void func_OnDetailOpened(EncyclopediaItemDTO item)
        {
            if (m_detailPopupOverlay == null || item == null)
            {
                return;
            }

            m_detailPopupOverlay.SetActive(true);

            if (m_detailNameText != null)
            {
                m_detailNameText.text = item.IsUnlocked ? item.Name : "??? (미해금)";
            }
            if (m_detailDescriptionText != null)
            {
                m_detailDescriptionText.text = item.IsUnlocked ? item.Description : "???";
            }

            bool isCG = (item.Category == "CG") && item.IsUnlocked;
            bool isSound = (item.Category == "Sound") && item.IsUnlocked;

            if (m_previewImage != null)
            {
                m_previewImage.gameObject.SetActive(isCG);
                if (isCG)
                {
                    var loadedSprite = Resources.Load<Sprite>(item.IconPath);
                    if (loadedSprite != null)
                    {
                        m_previewImage.sprite = loadedSprite;
                    }
                }
            }

            if (m_playButton != null)
            {
                m_playButton.gameObject.SetActive(isSound);
            }
        }

        /// <summary>
        /// [기능]: 뷰모델 상세창 닫기 이벤트 시 처리할 콜백입니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        private void func_OnDetailClosed()
        {
            if (m_detailPopupOverlay != null)
            {
                m_detailPopupOverlay.SetActive(false);
            }
        }
        #endregion

        #region 유니티 생명주기 (Unity Lifecycle)
        /// <summary>
        /// [기능]: 객체 파괴 시 뷰모델의 이벤트를 안전하게 해제하여 메모리 누수를 방지합니다.
        /// [작성자]: 윤승종
        /// [수정 날짜]: 2026-07-05
        /// </summary>
        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnDataChanged -= RefreshUI;
                m_viewModel.OnDetailOpened -= func_OnDetailOpened;
                m_viewModel.OnDetailClosed -= func_OnDetailClosed;
            }
        }
        #endregion
    }
}
