"""Render actual RF held-out site predictions, not model training predictions."""
from pathlib import Path
import csv, json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
ROOT=Path(__file__).resolve().parents[1]
font=Path('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
if font.exists():
    font_manager.fontManager.addfont(str(font));plt.rcParams['font.family']=font_manager.FontProperties(fname=str(font)).get_name()
plt.rcParams.update({'font.size':12,'text.color':'#183b47','axes.labelcolor':'#344d59','xtick.color':'#526975','ytick.color':'#526975','figure.facecolor':'#f6f8fa','axes.facecolor':'#f6f8fa','axes.spines.top':False,'axes.spines.right':False})
report=json.loads((ROOT/'evaluation/prediction-reproduction.json').read_text())
with (ROOT/'src/river_sr/training/base/v3/runs/base_v3_full_20260817_r2/reports/primary/site_oof_predictions.csv').open() as f:
    rows=[r for r in csv.DictReader(f) if r['model']=='rf']
colors=['#609bb0','#528b81','#c29345','#b45b52']
fig,axes=plt.subplots(1,2,figsize=(13,6.5),gridspec_kw={'width_ratios':[1,1.1]})
fig.subplots_adjust(left=.08,right=.96,top=.74,bottom=.22,wspace=.4)
fig.text(.055,.93,'误差集中在哪里，决定下一步投入什么',fontsize=23,fontweight='bold')
fig.text(.055,.865,'Base V3 · RF · 完整水系隔离 · 5,600 站点，每站 3 次留出预测取均值',fontsize=12,color='#526975')
ax=axes[0]
for (lo,hi),c in zip([(0,.72),(.72,.75),(.75,.8),(.8,10)],colors):
    group=[r for r in rows if lo<=float(r['observed'])<hi]
    ax.scatter([float(r['observed']) for r in group],[float(r['pred_mean']) for r in group],s=17,alpha=.55,color=c,linewidths=0)
end=max(float(r['observed']) for r in rows)+.015
ax.plot([.68,end],[.68,end],color='#8b9ca5',ls='--',lw=1)
ax.set(xlim=(.68,end),ylim=(.68,end),xlabel='实测 ⁸⁷Sr/⁸⁶Sr',ylabel='留出预测均值')
ax.set_title('高值系统性低估',loc='left',fontsize=15,pad=16)
ax.text(.02,.96,'虚线：预测 = 实测',transform=ax.transAxes,va='top',fontsize=11,color='#526975')
ax=axes[1]; bands=report['rf_bands']; ys=list(range(4))
ax.barh(ys,[b['sse_share']*100 for b in bands],color=colors,height=.49)
ax.set_yticks(ys,[f"{b['band']}\n{b['n']:,} 站点" for b in bands]);ax.invert_yaxis()
ax.set(xlim=(0,80),xlabel='占全部平方误差的比例（%）')
ax.set_title('少量高值站点贡献大部分误差',loc='left',fontsize=15,pad=16)
for i,b in enumerate(bands):ax.text(b['sse_share']*100+1.3,i,f"{b['sse_share']*100:.1f}%",va='center',fontsize=12,fontweight='bold')
ax.spines['left'].set_visible(False);ax.tick_params(axis='y',length=0,pad=8)
fig.text(.055,.115,'实测 ≥ 0.75：136 / 5,600 站点（2.43%），贡献 82.90% 的平方误差。',fontsize=13,fontweight='bold')
fig.text(.055,.055,'按实测值分层用于事后诊断；不能在未知地点直接用该标签路由模型。数据来自冻结原始预测，非新增训练。',fontsize=10,color='#526975')
fig.savefig(ROOT/'demo/assets/prediction-diagnostics.png',dpi=180)
plt.close(fig)
