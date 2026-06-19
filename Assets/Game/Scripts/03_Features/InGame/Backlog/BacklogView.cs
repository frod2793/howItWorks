using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using Domain.InGame;

namespace Features.InGame
{
    public class BacklogView : MonoBehaviour
    {
        [SerializeField] private GameObject m_backlogPanel;
        [SerializeField] private TMP_Text m_sceneInfoText;
        [SerializeField] private TMP_Text m_guideText;
        [SerializeField] private GameObject m_itemPrefab;
        [SerializeField] private RectTransform m_contentParent;

        private IBacklogViewModel m_viewModel;
        private List<GameObject> m_spawnedItems = new List<GameObject>();

        public void Initialize(IBacklogViewModel viewModel)
        {
            if (viewModel == null)
            {
                return;
            }
            m_viewModel = viewModel;
            m_viewModel.OnBacklogUpdated += UpdateUIValues;

            if (m_itemPrefab != null)
            {
                m_itemPrefab.SetActive(false);
            }
            UpdateUIValues();
        }

        private void OnDestroy()
        {
            if (m_viewModel != null)
            {
                m_viewModel.OnBacklogUpdated -= UpdateUIValues;
            }
        }

        private void UpdateUIValues()
        {
            if (m_viewModel == null)
            {
                return;
            }
            if (m_sceneInfoText != null)
            {
                m_sceneInfoText.text = $"{m_viewModel.CurrentSceneInfo} · {m_viewModel.Items.Count} 줄";
            }
        }

        public void func_Open()
        {
            if (m_backlogPanel != null)
            {
                m_backlogPanel.SetActive(true);
            }

            UpdateUIValues();

            for (int i = 0; i < m_spawnedItems.Count; i++)
            {
                if (m_spawnedItems[i] != null)
                {
                    Destroy(m_spawnedItems[i]);
                }
            }
            m_spawnedItems.Clear();

            if (m_viewModel == null || m_itemPrefab == null || m_contentParent == null)
            {
                return;
            }

            for (int i = 0; i < m_viewModel.Items.Count; i++)
            {
                var data = m_viewModel.Items[i];
                var inst = Instantiate(m_itemPrefab, m_contentParent);
                if (inst != null)
                {
                    inst.SetActive(true);
                    m_spawnedItems.Add(inst);

                    var speakerTrans = inst.transform.Find("SpeakerText");
                    var speakerText = speakerTrans != null ? speakerTrans.GetComponent<TMP_Text>() : null;
                    var contentTrans = inst.transform.Find("ContentText");
                    var contentText = contentTrans != null ? contentTrans.GetComponent<TMP_Text>() : null;
                    var branchTag = inst.transform.Find("BranchTag");

                    if (speakerText != null)
                    {
                        speakerText.text = data.SpeakerName;
                    }
                    if (contentText != null)
                    {
                        contentText.text = data.Content;
                    }
                    if (branchTag != null)
                    {
                        branchTag.gameObject.SetActive(data.HasBranchEffect);
                    }
                }
            }
        }

        public void func_Close()
        {
            if (m_backlogPanel != null)
            {
                m_backlogPanel.SetActive(false);
            }
        }
    }
}
